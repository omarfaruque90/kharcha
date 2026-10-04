import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/debt.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../providers/expense_provider.dart';
import '../providers/money_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/total_balance_provider.dart';
import '../utils/formatters.dart';
import '../widgets/brand_gradient_card.dart';
import '../widgets/branded_date_picker.dart';
import '../widgets/motion.dart';

/// Dhar/Baki — debts screen.
///
/// Tracks money the user has lent out ("Diyechi") and borrowed ("Niyechi"),
/// with due dates, settle flow and optional logging of the settlement as
/// an expense (borrowed) or income (lent).
///
/// Reads [Debt] rows through [DatabaseHelper] directly (Package A owns the
/// model + table), and logs settlements through [ExpenseProvider] /
/// [MoneyProvider] like the rest of the app.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

enum _DebtFilter { all, lent, borrowed, settled, splits }

/// Note prefix written by the split-bill feature (kind='lent').
const _splitPrefix = 'Split:';

class _DebtsScreenState extends State<DebtsScreen> {
  List<Debt> _debts = [];
  bool _loaded = false;
  _DebtFilter _filter = _DebtFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final debts = await DatabaseHelper.instance.getDebts();
      if (!mounted) return;
      setState(() {
        _debts = debts;
        _loaded = true;
      });
      // Refresh Home's "Lent out" amount.
      try {
        await context.read<TotalBalanceProvider>().refresh();
      } catch (_) {}
    } catch (_) {
      // Keep whatever data is on screen (possibly empty) and stop the
      // spinner so a DB failure can't leave the screen hanging.
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  List<Debt> get _visible {
    final list = _debts.toList();
    switch (_filter) {
      case _DebtFilter.lent:
        return list
            .where((d) => d.kind == 'lent' && !d.settled)
            .toList();
      case _DebtFilter.borrowed:
        return list
            .where((d) => d.kind == 'borrowed' && !d.settled)
            .toList();
      case _DebtFilter.settled:
        return list.where((d) => d.settled).toList();
      case _DebtFilter.splits:
        // Split debts still belong to All/Lent; this case only keeps the
        // switch exhaustive — the splits view is built from _splitGroups.
        return list
            .where((d) => d.note.trim().startsWith(_splitPrefix))
            .toList();
      case _DebtFilter.all:
        return list;
    }
  }

  /// Split-bill history grouped by the split title (the note suffix after
  /// 'Split:'), newest group first.
  List<_SplitGroup> get _splitGroups {
    final groups = <String, List<Debt>>{};
    for (final d in _debts) {
      final note = d.note.trim();
      if (!note.startsWith(_splitPrefix)) continue;
      final title = note.substring(_splitPrefix.length).trim();
      groups.putIfAbsent(title, () => []).add(d);
    }
    final out = groups.entries
        .map((e) => _SplitGroup(title: e.key, debts: e.value))
        .toList();
    out.sort((a, b) => b.latestDate.compareTo(a.latestDate));
    return out;
  }

  double _total(bool Function(Debt) test) =>
      _debts.where(test).fold(0.0, (sum, d) => sum + d.amount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pabo = _total((d) => d.kind == 'lent' && !d.settled);
    final dibo = _total((d) => d.kind == 'borrowed' && !d.settled);
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'debts_title')),
      ),
      floatingActionButton: _debts.isEmpty
          ? null
          : FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _DebtDialog(),
        ).then((saved) {
          if (saved == true) {
            _reload();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, 'debts_saved'))),
              );
            }
          }
        }),
        backgroundColor: kGold,
        foregroundColor: kDeepGreenDark,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'debts_add')),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: _TotalsCard(pabo: pabo, dibo: dibo),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _filterChip(
                          context, _DebtFilter.all, tr(context, 'all')),
                      _filterChip(
                          context, _DebtFilter.lent, tr(context, 'debts_diyechi')),
                      _filterChip(context, _DebtFilter.borrowed,
                          tr(context, 'debts_niyechi')),
                      _filterChip(context, _DebtFilter.settled,
                          tr(context, 'debts_settled')),
                      _filterChip(
                        context,
                        _DebtFilter.splits,
                        tr(context, 'debts_filter_splits'),
                        icon: Icons.groups_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: _filter == _DebtFilter.splits
                      ? _buildSplitsView(context)
                      : (visible.isEmpty
                          ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.handshake_outlined,
                                size: 56,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                tr(context, 'debts_no_debts'),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32),
                                child: Text(
                                  tr(context, 'debts_no_debts_sub'),
                                  style: theme.textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final d = visible[i];
                            return StaggeredEntrance(
                              key: ValueKey('debt-${d.id}'),
                              delayMs: i * 40,
                              child: _DebtTile(
                                debt: d,
                                onChanged: _reload,
                              ),
                            );
                          },
                        )),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(BuildContext context, _DebtFilter value, String label,
      {IconData? icon}) {
    final selected = _filter == value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = selected
        ? (dark ? kGoldLight : kGoldDark)
        : Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: labelColor),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: kGold.withValues(alpha: 0.25),
        labelStyle: TextStyle(
          color: labelColor,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: selected
              ? kGold
              : Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.4),
        ),
      ),
    );
  }

  /// Split-bill history: one card per split title, newest first.
  Widget _buildSplitsView(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _splitGroups;
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              tr(context, 'debts_no_splits'),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final g = groups[i];
        return StaggeredEntrance(
          key: ValueKey('split-$i-${g.title}'),
          delayMs: i * 40,
          child: _SplitGroupCard(group: g),
        );
      },
    );
  }
}

/// Deep-green hero card with Pabo / Dibo totals and the net line.
class _TotalsCard extends StatelessWidget {
  final double pabo;
  final double dibo;

  const _TotalsCard({required this.pabo, required this.dibo});

  @override
  Widget build(BuildContext context) {
    final net = pabo - dibo;
    return BrandGradientCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'debts_title'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: kGoldLight,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _totalCell(
                  context,
                  label: tr(context, 'debts_pabo'),
                  amount: pabo,
                  // Green reads well on the deep-green card in both themes.
                  color: const Color(0xFF86EFAC),
                  icon: Icons.arrow_upward,
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              Expanded(
                child: _totalCell(
                  context,
                  label: tr(context, 'debts_dibo'),
                  amount: dibo,
                  color: const Color(0xFFFCA5A5),
                  icon: Icons.arrow_downward,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: kGold.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr(context, 'debts_net'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${net >= 0 ? '+' : '−'} ${formatMoney(net.abs())}',
                  style: TextStyle(
                    color: net >= 0
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFCA5A5),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalCell(
    BuildContext context, {
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// One debt row: person, amount, due date, note; settle action or settled
/// badge; long-press deletes.
class _DebtTile extends StatelessWidget {
  final Debt debt;
  final VoidCallback onChanged;

  const _DebtTile({required this.debt, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lang = context.read<SettingsProvider>().language;
    final dateFmt = DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en');

    final overdue = debt.dueDate != null &&
        !debt.settled &&
        _day(debt.dueDate!).isBefore(_day(DateTime.now()));

    final amountColor = debt.settled
        ? theme.colorScheme.outline
        : debt.kind == 'lent'
            ? (dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
            : (dark ? const Color(0xFFF87171) : const Color(0xFFDC2626));

    final subtitleBits = <String>[
      dateFmt.format(debt.date),
    ];
    if (debt.dueDate != null) {
      subtitleBits.add(
          '${tr(context, 'debts_due')}: ${dateFmt.format(debt.dueDate!)}');
    }
    if (debt.note.trim().isNotEmpty) {
      subtitleBits.add(debt.note.trim());
    }

    return Card(
      child: ListTile(
        onLongPress: () => _confirmDelete(context, debt),
        leading: CircleAvatar(
          backgroundColor: amountColor.withValues(alpha: 0.15),
          child: Icon(
            debt.kind == 'lent' ? Icons.arrow_upward : Icons.arrow_downward,
            color: amountColor,
          ),
        ),
        title: Text(
          debt.person,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            decoration:
                debt.settled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleBits.join(' • ')),
            if (overdue)
              Text(
                tr(context, 'debts_overdue'),
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFF87171)
                      : const Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: debt.settled
            ? Icon(
                Icons.check_circle,
                color: theme.colorScheme.outline,
              )
            : TextButton.icon(
                onPressed: () => _settle(context, debt),
                icon: const Icon(Icons.check, size: 18),
                label: Text(tr(context, 'debts_mark_settled')),
                style: TextButton.styleFrom(
                  foregroundColor: dark
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF15803D),
                ),
              ),
      ),
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _settle(BuildContext context, Debt debt) async {
    await DatabaseHelper.instance.settleDebt(debt.id!);
    // Auto-update balance: lent settled = I got money back (income),
    // borrowed settled = I paid back (expense).
    final borrowed = debt.kind == 'borrowed';
    try {
      if (borrowed) {
        await context.read<ExpenseProvider>().add(Expense(
              amount: debt.amount,
              categoryId: 'others',
              date: DateTime.now(),
              note:
                  '${tr(context, 'debts_settle_expense_note')}: ${debt.person}',
              paymentMethod: 'cash',
            ));
      } else {
        await context.read<MoneyProvider>().addIncome(Income(
              amount: debt.amount,
              source: tr(context, 'debts_settle_income_source'),
              date: DateTime.now(),
              note: debt.person,
            ));
      }
    } catch (_) {}
    onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'debts_settled_msg'))),
    );
  }

  void _confirmDelete(BuildContext context, Debt debt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'debts_delete_title')),
        content: Text(tr(ctx, 'debts_delete_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteDebt(debt.id!);
              onChanged();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(tr(ctx, 'debts_deleted'))),
                );
              }
            },
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
  }
}

/// Add-debt dialog: person, amount, lent/borrowed selector, date, optional
/// due date, note.
class _DebtDialog extends StatefulWidget {
  const _DebtDialog();

  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  final _formKey = GlobalKey<FormState>();
  final _personCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _kind = 'lent';
  DateTime _date = DateTime.now();
  DateTime? _dueDate;

  @override
  void dispose() {
    _personCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<SettingsProvider>().language;
    final dateFmt = DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en');
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(tr(context, 'debts_add')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _personCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'debts_person'),
                  hintText: tr(context, 'debts_person_hint'),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? tr(context, 'debts_err_person_empty')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'amount'),
                  prefixText: '৳ ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) {
                    return tr(context, 'err_amount_invalid');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, 'debts_kind'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Center(
                          child: Text(tr(context, 'debts_diyechi'))),
                      selected: _kind == 'lent',
                      onSelected: (_) => setState(() => _kind = 'lent'),
                      selectedColor: kGold.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: _kind == 'lent'
                            ? (dark ? kGoldLight : kGoldDark)
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: _kind == 'lent'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(
                          child: Text(tr(context, 'debts_niyechi'))),
                      selected: _kind == 'borrowed',
                      onSelected: (_) =>
                          setState(() => _kind = 'borrowed'),
                      selectedColor: kGold.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                        color: _kind == 'borrowed'
                            ? (dark ? kGoldLight : kGoldDark)
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: _kind == 'borrowed'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showBrandedDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                    '${tr(context, 'date')}: ${dateFmt.format(_date)}'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showBrandedDatePicker(
                          context: context,
                          initialDate: _dueDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() => _dueDate = picked);
                        }
                      },
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(_dueDate == null
                          ? tr(context, 'debts_no_due_date')
                          : '${tr(context, 'debts_due')}: ${dateFmt.format(_dueDate!)}'),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      tooltip: tr(context, 'debts_no_due_date'),
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'note'),
                  hintText: tr(context, 'debts_note_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'cancel')),
        ),
        PressableScale(
          pressedScale: 0.97,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kGoldLight, kGold, kGoldDark],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(tr(context, 'save')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                // Dark text on the gold gradient stays readable in
                // both light and dark mode.
                foregroundColor: kDeepGreenDark,
                iconColor: kDeepGreenDark,
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await DatabaseHelper.instance.insertDebt(Debt(
      id: Debt.newId(),
      person: _personCtrl.text.trim(),
      amount: double.parse(_amountCtrl.text.trim()),
      kind: _kind,
      date: _date,
      dueDate: _dueDate,
      note: _noteCtrl.text.trim(),
      settled: false,
      updatedAt: DateTime.now(),
    ));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

/// One split bill: the debts sharing the same 'Split: <title>' note.
class _SplitGroup {
  final String title;
  final List<Debt> debts;

  _SplitGroup({required this.title, required List<Debt> debts})
      : debts = List.of(debts)
          ..sort((a, b) {
            // Unsettled people first, then newest.
            if (a.settled != b.settled) return a.settled ? 1 : -1;
            return b.date.compareTo(a.date);
          });

  double get total => debts.fold(0.0, (sum, d) => sum + d.amount);

  DateTime get latestDate =>
      debts.map((d) => d.date).reduce((a, b) => a.isAfter(b) ? a : b);

  List<String> get stillOwing =>
      debts.where((d) => !d.settled).map((d) => d.person).toList();
}

/// One split-bill card: title, summed total, who still owes, and the
/// per-person rows with their owed/settled state.
class _SplitGroupCard extends StatelessWidget {
  final _SplitGroup group;

  const _SplitGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lang = context.read<SettingsProvider>().language;
    final dateFmt = DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en');
    final stillOwing = group.stillOwing;
    final owedColor =
        dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: kGold.withValues(alpha: 0.18),
          child: Icon(
            Icons.groups_outlined,
            color: dark ? kGoldLight : kGoldDark,
          ),
        ),
        title: Text(
          group.title,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${formatMoney(group.total)} • ${stillOwing.isEmpty ? tr(context, 'debts_settled') : '${tr(context, 'debts_split_still_owes')}: ${stillOwing.join(', ')}'}',
        ),
        children: [
          for (final d in group.debts)
            ListTile(
              dense: true,
              leading: Icon(
                d.settled ? Icons.check_circle_outline : Icons.person_outline,
                color: d.settled ? theme.colorScheme.outline : owedColor,
              ),
              title: Text(d.person),
              subtitle: Text(dateFmt.format(d.date)),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(d.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          d.settled ? theme.colorScheme.outline : owedColor,
                    ),
                  ),
                  Text(
                    d.settled
                        ? tr(context, 'debts_settled')
                        : tr(context, 'debts_split_owed'),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          d.settled ? theme.colorScheme.outline : owedColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

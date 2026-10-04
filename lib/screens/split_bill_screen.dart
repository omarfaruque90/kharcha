import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/debt.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Split a shared bill: the user's own share becomes a regular expense,
/// each friend's share becomes a "lent" debt so it can be settled later.
///
/// Assumptions about the Package-A Debt API (models/debt.dart):
///   class Debt {
///     static String newId();
///     String? id; String person; double amount; String kind;
///     DateTime date; DateTime? dueDate; String note;
///     bool settled; DateTime updatedAt;
///     Debt({id, required person, required amount, required kind,
///           required date, this.dueDate, this.note = '',
///           this.settled = false, DateTime? updatedAt});
///   }
/// and DatabaseHelper.instance.insertDebt(Debt).
class SplitBillScreen extends StatefulWidget {
  const SplitBillScreen({super.key});

  @override
  State<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends State<SplitBillScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final List<_PersonRow> _rows = [];
  bool _saving = false;
  String _debtKind = 'lent'; // 'lent' (diyechi) or 'borrowed' (niyechi)

  @override
  void initState() {
    super.initState();
    _rows.addAll([
      _PersonRow(isMe: true),
      _PersonRow(isMe: false),
    ]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _totalCtrl.dispose();
    for (final r in _rows) {
      r.nameCtrl.dispose();
      r.amountCtrl.dispose();
    }
    super.dispose();
  }

  double get _total => double.tryParse(_totalCtrl.text.trim()) ?? 0;

  double _rowAmount(_PersonRow r) =>
      double.tryParse(r.amountCtrl.text.trim()) ?? 0;

  double get _sum => _rows.fold(0.0, (s, r) => s + _rowAmount(r));

  /// Fills each row's amount with total / row count (rounded to 2 decimals).
  void _equalSplit() {
    if (_total <= 0 || _rows.isEmpty) return;
    final share = (_total / _rows.length * 100).round() / 100;
    setState(() {
      for (final r in _rows) {
        r.amountCtrl.text =
            share.truncateToDouble() == share ? share.toStringAsFixed(0) : share.toStringAsFixed(2);
      }
    });
  }

  void _addPerson() {
    setState(() => _rows.add(_PersonRow()));
  }

  void _removePerson(int index) {
    setState(() {
      final removed = _rows.removeAt(index);
      removed.nameCtrl.dispose();
      removed.amountCtrl.dispose();
    });
  }

  Future<void> _save(String lang) async {
    if (!_formKey.currentState!.validate()) return;
    int? meIndex;
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].isMe) {
        if (meIndex != null) {
          meIndex = null;
          break; // more than one "me" — invalid
        }
        meIndex = i;
      }
    }
    if (meIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'split_err_one_me'))),
      );
      return;
    }
    final idx = meIndex;
    final meAmount = _rowAmount(_rows[idx]);
    if (meAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'split_err_amount'))),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final title = _titleCtrl.text.trim();
    try {
      // My own share → a normal expense.
      await context.read<ExpenseProvider>().add(
            Expense(
              amount: meAmount,
              categoryId: 'others',
              date: DateTime.now(),
              note: 'Split: $title',
              paymentMethod: 'cash',
            ),
          );
      // Every other person's share → a "lent" debt I can settle later.
      for (var i = 0; i < _rows.length; i++) {
        if (i == idx) continue;
        final name = _rows[i].nameCtrl.text.trim();
        final amount = _rowAmount(_rows[i]);
        await DatabaseHelper.instance.insertDebt(
          Debt(
            person: name,
            amount: amount,
            kind: _debtKind,
            date: DateTime.now(),
            note: 'Split: $title',
            settled: false,
          ),
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(tr(context, 'split_saved'))),
      );
      navigator.pop();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr(context, 'split_save_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateTitle(String? v) =>
      (v ?? '').trim().isEmpty ? tr(context, 'split_err_title') : null;

  String? _validateTotal(String? v) {
    final parsed = double.tryParse((v ?? '').trim());
    return (parsed == null || parsed <= 0)
        ? tr(context, 'split_err_amount')
        : null;
  }

  String? _validateName(String? v) =>
      (v ?? '').trim().isEmpty ? tr(context, 'split_err_name') : null;

  String? _validateRowAmount(String? v) {
    final parsed = double.tryParse((v ?? '').trim());
    return (parsed == null || parsed <= 0)
        ? tr(context, 'split_err_amount')
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sum = _sum;
    final total = _total;
    final mismatch = sum > 0 && total > 0 && (sum - total).abs() > 0.009;
    final meCount = _rows.where((r) => r.isMe).length;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'split_title'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Lent / Borrowed selector.
            StaggeredEntrance(
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'lent',
                    icon: const Icon(Icons.handshake_outlined),
                    label: Text(tr(context, 'debt_lent')),
                  ),
                  ButtonSegment(
                    value: 'borrowed',
                    icon: const Icon(Icons.call_received_outlined),
                    label: Text(tr(context, 'debt_borrowed')),
                  ),
                ],
                selected: {_debtKind},
                onSelectionChanged: (s) =>
                    setState(() => _debtKind = s.first),
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              child: TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr(context, 'split_bill_title'),
                  hintText: tr(context, 'split_bill_title_hint'),
                  border: const OutlineInputBorder(),
                ),
                validator: _validateTitle,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              delayMs: 60,
              child: TextFormField(
                controller: _totalCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: tr(context, 'split_total'),
                  prefixText: '৳ ',
                  prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: _validateTotal,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 20),
            StaggeredEntrance(
              delayMs: 120,
              child: _sectionLabel(context, tr(context, 'split_people')),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              delayMs: 150,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _personRow(ctx, i),
              ),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              delayMs: 180,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addPerson,
                      icon: const Icon(Icons.person_add_outlined),
                      label: Text(tr(context, 'split_add_person')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: total > 0 ? _equalSplit : null,
                      icon: const Icon(Icons.balance_outlined),
                      label: Text(tr(context, 'split_equal')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            StaggeredEntrance(
              delayMs: 210,
              child: _sectionLabel(context, tr(context, 'split_summary')),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              delayMs: 240,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final r in _rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.nameCtrl.text.trim().isEmpty
                                      ? tr(context, 'split_unnamed')
                                      : r.nameCtrl.text.trim(),
                                  style: TextStyle(
                                    fontWeight: r.isMe
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: r.isMe
                                        ? kGold
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (r.isMe)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kGold.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    tr(context, 'split_me_badge'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: kGoldDark,
                                    ),
                                  ),
                                ),
                              Text(
                                formatMoney(_rowAmount(r)),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, 'split_sum'),
                              style:
                                  theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            formatMoney(sum),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (mismatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tr(context, 'split_mismatch')
                                      .replaceAll(
                                          '{diff}',
                                          formatMoney(
                                              (total - sum).abs())),
                                  style: TextStyle(
                                    color: dark
                                        ? kGoldLight
                                        : kGoldDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (meCount != 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tr(context, 'split_err_one_me'),
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            StaggeredEntrance(
              delayMs: 270,
              child: PressableScale(
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
                    onPressed: _saving
                        ? null
                        : () => _save(
                            context
                                .read<SettingsProvider>()
                                .language),
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kDeepGreenDark,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(tr(context, 'save')),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: kDeepGreenDark,
                      iconColor: kDeepGreenDark,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One person row: name field + amount field + "this is me" + remove.
  Widget _personRow(BuildContext context, int index) {
    final r = _rows[index];
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: r.isMe
              ? kGold.withValues(alpha: 0.7)
              : theme.colorScheme.outlineVariant,
          width: r.isMe ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: r.nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: tr(context, 'split_name'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  validator: _validateName,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: r.amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '৳',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  validator: _validateRowAmount,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: tr(context, 'split_remove_person'),
                onPressed: _rows.length > 1
                    ? () => _removePerson(index)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.redAccent,
              ),
            ],
          ),
          InkWell(
            onTap: () => setState(() {
              for (final other in _rows) {
                other.isMe = false;
              }
              r.isMe = true;
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: r.isMe,
                    activeColor: kGold,
                    checkColor: kDeepGreenDark,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        for (final other in _rows) {
                          other.isMe = false;
                        }
                      }
                      r.isMe = v ?? false;
                    }),
                  ),
                  Expanded(
                    child: Text(
                      tr(context, 'split_this_is_me'),
                      style: TextStyle(
                        fontSize: 13,
                        color: dark
                            ? kGoldLight
                            : kGoldDark,
                        fontWeight: r.isMe
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Premium section header: small caps gold, letterspaced.
  Widget _sectionLabel(BuildContext context, String text) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: dark ? kGoldLight : kGoldDark,
      ),
    );
  }
}

/// Holds the controllers and "is me" flag for one person row.
class _PersonRow {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  bool isMe;

  _PersonRow({this.isMe = false});
}

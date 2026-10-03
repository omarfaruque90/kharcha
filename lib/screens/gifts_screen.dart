import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/gift.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/motion.dart';

/// Gift tracker (Package AR): gifts given and received, filterable by
/// kind with Given/Received/All chips. New gifts are recorded with
/// person, occasion, amount, kind, date, and note. Upcoming occasions
/// are reminded by [GiftReminderService.checkUpcoming].
class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  List<Gift> _gifts = [];
  bool _loading = true;
  // 'all' | 'given' | 'received'
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final gifts = await DatabaseHelper.instance.getGifts();
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Gift> get _filtered {
    final list = _filter == 'all'
        ? _gifts
        : _gifts.where((g) => g.kind == _filter).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double _totalFor(String kind) =>
      _gifts.where((g) => g.kind == kind).fold(0.0, (s, g) => s + g.amount);

  Future<void> _confirmDelete(Gift gift) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'gift_delete_title')),
        content: Text(tr(ctx, 'gift_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok == true && gift.id != null) {
      await DatabaseHelper.instance.deleteGift(gift.id!);
      await _reload();
    }
  }

  Future<void> _showAddDialog() async {
    final personCtrl = TextEditingController();
    final occasionCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String kind = 'given';
    final dateState = _DateField(date: DateTime.now());

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr(ctx, 'gift_new_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(tr(ctx, 'gift_given')),
                      selected: kind == 'given',
                      onSelected: (_) =>
                          setDialogState(() => kind = 'given'),
                    ),
                    ChoiceChip(
                      label: Text(tr(ctx, 'gift_received')),
                      selected: kind == 'received',
                      onSelected: (_) =>
                          setDialogState(() => kind = 'received'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: personCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'gift_person'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: occasionCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'gift_occasion'),
                    hintText: tr(ctx, 'gift_occasion_hint'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'amount'),
                    prefixText: '৳ ',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dateState.date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => dateState.date = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_fmtDate(context, dateState.date)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: tr(ctx, 'note'),
                    hintText: tr(ctx, 'note_hint'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr(ctx, 'cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tr(ctx, 'save')),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final person = personCtrl.text.trim();
    if (person.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'gift_invalid'))),
      );
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    await DatabaseHelper.instance.insertGift(
      Gift(
        id: Gift.newId(),
        person: person,
        occasion: occasionCtrl.text.trim(),
        amount: amount < 0 ? 0 : amount,
        kind: kind,
        date: dateState.date,
        note: noteCtrl.text.trim(),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final list = _filtered;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'gift_title'))),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: tr(context, 'gift_new_title'),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StaggeredEntrance(
                  child: _SummaryCard(
                    dark: dark,
                    given: _totalFor('given'),
                    received: _totalFor('received'),
                  ),
                ),
                const SizedBox(height: 12),
                StaggeredEntrance(
                  delayMs: 60,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in const ['all', 'given', 'received'])
                        ChoiceChip(
                          label: Text(tr(context,
                              f == 'all' ? 'all' : 'gift_$f')),
                          selected: _filter == f,
                          onSelected: (_) =>
                              setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      tr(context, 'gift_empty'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final gift = list[i];
                      return StaggeredEntrance(
                        key: ValueKey('gift-${gift.id}'),
                        delayMs: (80 + i * 40).clamp(0, 500).toInt(),
                        child: _GiftCard(
                          gift: gift,
                          dark: dark,
                          onDelete: () => _confirmDelete(gift),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

/// Locale-aware short date (yMMMd), same convention as debts/home screens.
String _fmtDate(BuildContext context, DateTime d) {
  final lang = context.read<SettingsProvider>().language;
  return DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(d);
}

class _DateField {
  DateTime date;
  _DateField({required this.date});
}

/// Summary card: total given vs total received.
class _SummaryCard extends StatelessWidget {
  final bool dark;
  final double given;
  final double received;

  const _SummaryCard({
    required this.dark,
    required this.given,
    required this.received,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? kDeepGreenCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Total(
              theme: theme,
              label: tr(context, 'gift_given'),
              value: formatMoney(given),
              icon: Icons.card_giftcard_outlined,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          Expanded(
            child: _Total(
              theme: theme,
              label: tr(context, 'gift_received'),
              value: formatMoney(received),
              icon: Icons.redeem_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final String value;
  final IconData icon;

  const _Total({
    required this.theme,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: kGold, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// One gift card: person + occasion, amount, kind badge, date; delete.
class _GiftCard extends StatelessWidget {
  final Gift gift;
  final bool dark;
  final VoidCallback onDelete;

  const _GiftCard({
    required this.gift,
    required this.dark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGiven = gift.kind == 'given';
    final badgeColor = isGiven
        ? kGold
        : (dark ? kGoldLight : kGoldDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? kDeepGreenCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              tr(context, 'gift_${gift.kind}'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gift.person,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${gift.occasion.isNotEmpty ? '${gift.occasion} · ' : ''}'
                  '${_fmtDate(context, gift.date)}'
                  '${gift.note.isNotEmpty ? ' · ${gift.note}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(gift.amount),
            style: theme.textTheme.titleSmall?.copyWith(
              color: dark ? kGoldLight : kGoldDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: theme.colorScheme.error,
            tooltip: tr(context, 'delete'),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

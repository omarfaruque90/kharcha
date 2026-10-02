import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/motion.dart';

const List<String> kPaymentMethods = ['cash', 'bkash', 'card', 'other'];

/// Add a new expense, or edit [expense] when provided.
/// Used both as the "Add" bottom-nav tab and as a pushed edit page.
class AddExpenseScreen extends StatefulWidget {
  final Expense? expense;
  final VoidCallback? onSaved;

  const AddExpenseScreen({super.key, this.expense, this.onSaved});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _categoryId = 'food';
  DateTime _date = DateTime.now();
  String _payment = 'cash';
  bool _showSuccess = false;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null) {
      final whole = e.amount.truncateToDouble() == e.amount;
      _amountCtrl.text =
          whole ? e.amount.toStringAsFixed(0) : e.amount.toString();
      _noteCtrl.text = e.note;
      _categoryId = e.categoryId;
      _date = e.date;
      _payment = e.paymentMethod;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(String lang) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: Locale(lang),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save(String lang) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final provider = context.read<ExpenseProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_isEdit) {
      final updated = widget.expense!.copyWith(
        amount: amount,
        categoryId: _categoryId,
        date: _date,
        note: _noteCtrl.text.trim(),
        paymentMethod: _payment,
      );
      await provider.update(updated);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('msg_updated', lang))),
      );
      navigator.pop();
    } else {
      await provider.add(
        Expense(
          amount: amount,
          categoryId: _categoryId,
          date: _date,
          note: _noteCtrl.text.trim(),
          paymentMethod: _payment,
        ),
      );
      if (!mounted) return;
      // Animated success check, then reset and go home.
      setState(() => _showSuccess = true);
      await Future.delayed(const Duration(milliseconds: 950));
      if (!mounted) return;
      setState(() => _showSuccess = false);
      _amountCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _categoryId = 'food';
        _date = DateTime.now();
        _payment = 'cash';
      });
      widget.onSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final theme = Theme.of(context);
    final dateLabel =
        DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en').format(_date);

    String? validateAmount(String? v) {
      final text = (v ?? '').trim();
      if (text.isEmpty) return AppStrings.get('err_amount_empty', lang);
      final parsed = double.tryParse(text);
      if (parsed == null || parsed <= 0) {
        return AppStrings.get('err_amount_invalid', lang);
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, _isEdit ? 'edit_expense' : 'add_expense')),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(context, 'amount'),
                hintText: tr(context, 'amount_hint'),
                prefixText: '৳ ',
                border: const OutlineInputBorder(),
              ),
              validator: validateAmount,
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'category'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: kCategories.length,
              itemBuilder: (ctx, i) {
                final c = kCategories[i];
                final selected = _categoryId == c.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _categoryId = c.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    transform: Matrix4.identity()
                      ..scale(selected ? 1.06 : 1.0),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected
                          ? c.color.withValues(alpha: 0.18)
                          : theme.colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: selected
                            ? c.color
                            : theme.colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: selected
                              ? c.color.withValues(alpha: 0.35)
                              : Colors.transparent,
                          blurRadius: selected ? 8 : 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(c.icon, color: c.color, size: 26),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.categoryName(c.id, lang),
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.calendar_today),
              title: Text(tr(context, 'date')),
              subtitle: Text(dateLabel),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => _pickDate(lang),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr(context, 'note'),
                hintText: tr(context, 'note_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'payment_method'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in kPaymentMethods)
                  ChoiceChip(
                    label: Text(AppStrings.paymentName(m, lang)),
                    selected: _payment == m,
                    onSelected: (_) => setState(() => _payment = m),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            PressableScale(
              pressedScale: 0.97,
              child: FilledButton.icon(
                onPressed: () => _save(lang),
                icon: const Icon(Icons.check),
                label: Text(tr(context, 'save')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
      // Animated success check overlay.
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: _showSuccess ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showSuccess,
            child: Container(
              color: Colors.black54,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_showSuccess),
                  tween: const Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

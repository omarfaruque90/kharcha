import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../l10n/app_strings.dart';
import '../main.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';
import '../widgets/motion.dart';

/// Monthly calendar view of expenses. Days with expenses show gold dots;
/// tapping a day lists that day's expenses below the calendar.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = now;
    _selectedDay = _dayKey(now);
  }

  /// Strips a DateTime down to its calendar day (used as map keys).
  static DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final expenses = context.watch<ExpenseProvider>().expenses;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // Group expenses by day; rebuilt from the watched list every build.
    final byDay = <DateTime, List<Expense>>{};
    for (final expense in expenses) {
      final key = _dayKey(expense.date);
      (byDay[key] ??= []).add(expense);
    }

    final selectedExpenses = byDay[_dayKey(_selectedDay)] ?? const <Expense>[];
    final dayTotal =
        selectedExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final dayLabel = DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en')
        .format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'cal_title')),
      ),
      body: Column(
        children: [
          TableCalendar<Expense>(
            firstDay: DateTime(2020),
            lastDay: DateTime(2030),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Month',
            },
            eventLoader: (day) => byDay[_dayKey(day)] ?? const <Expense>[],
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
            calendarStyle: CalendarStyle(
              markerDecoration: const BoxDecoration(
                color: kGold,
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: kGold,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                color: kDeepGreenDark,
                fontWeight: FontWeight.bold,
              ),
              todayDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark ? kGold : kDeepGreen,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StaggeredEntrance(
              key: ValueKey(_dayKey(_selectedDay)),
              child: selectedExpenses.isEmpty
                  ? _EmptyDay(
                      headerText: '$dayLabel — ${formatMoney(0)}',
                    )
                  : ListView.builder(
                      itemCount: selectedExpenses.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              '$dayLabel — ${formatMoney(dayTotal)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }
                        return ExpenseTile(
                          expense: selectedExpenses[index - 1],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the selected day has no expenses.
class _EmptyDay extends StatelessWidget {
  final String headerText;

  const _EmptyDay({required this.headerText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            headerText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 48,
                color: theme.disabledColor,
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, 'cal_no_expenses'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.hintColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

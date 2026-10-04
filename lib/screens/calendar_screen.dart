import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../data/bd_holidays.dart';
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

  /// Memoized day-grouping: rebuilding it on every build (e.g. each day
  /// tap) is O(n) over all expenses, so recompute only when the watched
  /// list instance changes.
  List<Expense>? _lastGrouped;
  Map<DateTime, List<Expense>> _byDayCache = const {};

  Map<DateTime, List<Expense>> _byDay(List<Expense> expenses) {
    if (!identical(expenses, _lastGrouped)) {
      final byDay = <DateTime, List<Expense>>{};
      for (final expense in expenses) {
        final key = _dayKey(expense.date);
        (byDay[key] ??= []).add(expense);
      }
      _lastGrouped = expenses;
      _byDayCache = byDay;
    }
    return _byDayCache;
  }

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

    // Group expenses by day; memoized — rebuilt only when the list changes.
    final byDay = _byDay(expenses);

    final selectedExpenses = byDay[_dayKey(_selectedDay)] ?? const <Expense>[];
    final dayTotal =
        selectedExpenses.fold(0.0, (sum, e) => sum + e.amount);
    final dayLabel = DateFormat.yMMMd(lang == 'bn' ? 'bn' : 'en')
        .format(_selectedDay);
    final holiday = bdHolidayOn(_dayKey(_selectedDay));
    final holidayName =
        holiday == null ? null : (lang == 'bn' ? holiday.bn : holiday.en);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'cal_title')),
      ),
      body: Column(
        children: [
          TableCalendar<Expense>(
            firstDay: DateTime(2020),
            lastDay: DateTime(2040, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: {
              CalendarFormat.month: tr(context, 'month'),
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
            holidayPredicate: (day) => isBdHoliday(day),
            calendarStyle: CalendarStyle(
              holidayTextStyle: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
              holidayDecoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
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
                      holidayName: holidayName,
                    )
                  : ListView.builder(
                      itemCount: selectedExpenses.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$dayLabel — ${formatMoney(dayTotal)}',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (holidayName != null) ...[
                                  const SizedBox(height: 4),
                                  _HolidayChip(label: holidayName),
                                ],
                              ],
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

/// Small red chip showing the holiday name for the selected day.
class _HolidayChip extends StatelessWidget {
  final String label;

  const _HolidayChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: error.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_outlined, size: 14, color: error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: error,
                fontWeight: FontWeight.w600,
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
  final String? holidayName;

  const _EmptyDay({required this.headerText, this.holidayName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headerText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (holidayName != null) ...[
                const SizedBox(height: 4),
                _HolidayChip(label: holidayName!),
              ],
            ],
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

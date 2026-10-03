/// Bangladesh holidays: government, religious and cultural.
///
/// Fixed Gregorian holidays are exact. Islamic holidays use the
/// tabular (arithmetic) calendar — within ±1 day of the actual
/// moon-sighting date. Hindu/Buddhist lunar dates are approximate.
/// Covers 2024–2040.
library;

/// A holiday with English + Bangla names.
class BdHoliday {
  final String en;
  final String bn;
  const BdHoliday(this.en, this.bn);
}

/// Fixed Gregorian holidays (month-day) -> holiday.
const Map<String, BdHoliday> _fixed = {
  '2-21': BdHoliday('Shaheed Day (Language Martyrs Day)',
      'শহীদ দিবস (ভাষা শহীদ দিবস)'),
  '3-17': BdHoliday("Sheikh Mujibur Rahman's Birthday",
      'বঙ্গবন্ধুর জন্মদিবস'),
  '3-26': BdHoliday('Independence Day', 'স্বাধীনতা দিবস'),
  '4-14': BdHoliday('Bengali New Year (Pohela Boishakh)', 'বাংলা নববর্ষ'),
  '5-1': BdHoliday('May Day', 'মে দিবস'),
  '8-15': BdHoliday('National Mourning Day', 'জাতীয় শোক দিবস'),
  '12-16': BdHoliday('Victory Day', 'বিজয় দিবস'),
  '12-25': BdHoliday('Christmas Day', 'বড়দিন'),
};

/// Easter (month-day) per year.
const Map<int, String> _easter = {
  2024: '3-31', 2025: '4-20', 2026: '4-5', 2027: '3-28', 2028: '4-16', 2029: '4-1', 2030: '4-21', 2031: '4-13', 2032: '3-28', 2033: '4-17', 2034: '4-9', 2035: '3-25', 2036: '4-13', 2037: '4-5', 2038: '4-25', 2039: '4-10', 2040: '4-1',
};

/// Buddha Purnima (month-day) per year (approximate).
const Map<int, String> _buddhaPurnima = {
  2024: '5-23', 2025: '5-12', 2026: '5-1', 2027: '5-20', 2028: '5-9', 2029: '5-28', 2030: '5-17', 2031: '5-7', 2032: '5-25', 2033: '5-14', 2034: '5-4', 2035: '5-23', 2036: '5-11', 2037: '5-1', 2038: '5-20', 2039: '5-9', 2040: '5-27',
};

/// Durga Puja Dashami (month-day) per year (approximate).
const Map<int, String> _durgaPuja = {
  2024: '10-13', 2025: '10-2', 2026: '10-21', 2027: '10-10', 2028: '9-28', 2029: '10-17', 2030: '10-6', 2031: '9-28', 2032: '10-15', 2033: '10-4', 2034: '10-23', 2035: '10-12', 2036: '10-1', 2037: '10-20', 2038: '10-9', 2039: '9-29', 2040: '10-17',
};

/// Islamic holidays: full Gregorian date -> holiday key.
/// Precomputed with the tabular Islamic calendar (±1 day vs
/// moon sighting).
const Map<String, String> _islamicDates = {
'2024-02-07': 'meraj',
    '2024-02-25': 'barat',
    '2024-04-06': 'qadr',
    '2024-04-10': 'fitr1',
    '2024-04-11': 'fitr2',
    '2024-04-12': 'fitr3',
    '2024-06-17': 'adha1',
    '2024-06-18': 'adha2',
    '2024-06-19': 'adha3',
    '2024-07-16': 'ashura',
    '2024-09-15': 'milad',
    '2025-01-26': 'meraj',
    '2025-02-13': 'barat',
    '2025-03-26': 'qadr',
    '2025-03-30': 'fitr1',
    '2025-03-31': 'fitr2',
    '2025-04-01': 'fitr3',
    '2025-06-06': 'adha1',
    '2025-06-07': 'adha2',
    '2025-06-08': 'adha3',
    '2025-07-06': 'ashura',
    '2025-09-05': 'milad',
    '2026-01-16': 'meraj',
    '2026-02-03': 'barat',
    '2026-03-16': 'qadr',
    '2026-03-20': 'fitr1',
    '2026-03-21': 'fitr2',
    '2026-03-22': 'fitr3',
    '2026-05-27': 'adha1',
    '2026-05-28': 'adha2',
    '2026-05-29': 'adha3',
    '2026-06-25': 'ashura',
    '2026-08-25': 'milad',
    '2027-01-05': 'meraj',
    '2027-01-23': 'barat',
    '2027-03-05': 'qadr',
    '2027-03-09': 'fitr1',
    '2027-03-10': 'fitr2',
    '2027-03-11': 'fitr3',
    '2027-05-16': 'adha1',
    '2027-05-17': 'adha2',
    '2027-05-18': 'adha3',
    '2027-06-15': 'ashura',
    '2027-08-15': 'milad',
    '2027-12-26': 'meraj',
    '2028-01-13': 'barat',
    '2028-02-23': 'qadr',
    '2028-02-27': 'fitr1',
    '2028-02-28': 'fitr2',
    '2028-02-29': 'fitr3',
    '2028-05-05': 'adha1',
    '2028-05-06': 'adha2',
    '2028-05-07': 'adha3',
    '2028-06-03': 'ashura',
    '2028-08-03': 'milad',
    '2028-12-14': 'meraj',
    '2029-01-01': 'barat',
    '2029-02-11': 'qadr',
    '2029-02-15': 'fitr1',
    '2029-02-16': 'fitr2',
    '2029-02-17': 'fitr3',
    '2029-04-24': 'adha1',
    '2029-04-25': 'adha2',
    '2029-04-26': 'adha3',
    '2029-05-23': 'ashura',
    '2029-07-23': 'milad',
    '2029-12-03': 'meraj',
    '2029-12-21': 'barat',
    '2030-01-31': 'qadr',
    '2030-02-04': 'fitr1',
    '2030-02-05': 'fitr2',
    '2030-02-06': 'fitr3',
    '2030-04-13': 'adha1',
    '2030-04-14': 'adha2',
    '2030-04-15': 'adha3',
    '2030-05-13': 'ashura',
    '2030-07-13': 'milad',
    '2030-11-23': 'meraj',
    '2030-12-11': 'barat',
    '2031-01-21': 'qadr',
    '2031-01-25': 'fitr1',
    '2031-01-26': 'fitr2',
    '2031-01-27': 'fitr3',
    '2031-04-03': 'adha1',
    '2031-04-04': 'adha2',
    '2031-04-05': 'adha3',
    '2031-05-02': 'ashura',
    '2031-07-02': 'milad',
    '2031-11-12': 'meraj',
    '2031-11-30': 'barat',
    '2032-01-10': 'qadr',
    '2032-01-14': 'fitr1',
    '2032-01-15': 'fitr2',
    '2032-01-16': 'fitr3',
    '2032-03-22': 'adha1',
    '2032-03-23': 'adha2',
    '2032-03-24': 'adha3',
    '2032-04-20': 'ashura',
    '2032-06-20': 'milad',
    '2032-10-31': 'meraj',
    '2032-11-18': 'barat',
    '2032-12-29': 'qadr',
    '2033-01-02': 'fitr1',
    '2033-01-03': 'fitr2',
    '2033-01-04': 'fitr3',
    '2033-03-11': 'adha1',
    '2033-03-12': 'adha2',
    '2033-03-13': 'adha3',
    '2033-04-10': 'ashura',
    '2033-06-10': 'milad',
    '2033-10-21': 'meraj',
    '2033-11-08': 'barat',
    '2033-12-19': 'qadr',
    '2033-12-23': 'fitr1',
    '2033-12-24': 'fitr2',
    '2033-12-25': 'fitr3',
    '2034-03-01': 'adha1',
    '2034-03-02': 'adha2',
    '2034-03-03': 'adha3',
    '2034-03-30': 'ashura',
    '2034-05-30': 'milad',
    '2034-10-10': 'meraj',
    '2034-10-28': 'barat',
    '2034-12-08': 'qadr',
    '2034-12-12': 'fitr1',
    '2034-12-13': 'fitr2',
    '2034-12-14': 'fitr3',
    '2035-02-18': 'adha1',
    '2035-02-19': 'adha2',
    '2035-02-20': 'adha3',
    '2035-03-19': 'ashura',
    '2035-05-19': 'milad',
    '2035-09-29': 'meraj',
    '2035-10-17': 'barat',
    '2035-11-27': 'qadr',
    '2035-12-01': 'fitr1',
    '2035-12-02': 'fitr2',
    '2035-12-03': 'fitr3',
    '2036-02-07': 'adha1',
    '2036-02-08': 'adha2',
    '2036-02-09': 'adha3',
    '2036-03-08': 'ashura',
    '2036-05-08': 'milad',
    '2036-09-18': 'meraj',
    '2036-10-06': 'barat',
    '2036-11-16': 'qadr',
    '2036-11-20': 'fitr1',
    '2036-11-21': 'fitr2',
    '2036-11-22': 'fitr3',
    '2037-01-27': 'adha1',
    '2037-01-28': 'adha2',
    '2037-01-29': 'adha3',
    '2037-02-25': 'ashura',
    '2037-04-27': 'milad',
    '2037-09-07': 'meraj',
    '2037-09-25': 'barat',
    '2037-11-05': 'qadr',
    '2037-11-09': 'fitr1',
    '2037-11-10': 'fitr2',
    '2037-11-11': 'fitr3',
    '2038-01-16': 'adha1',
    '2038-01-17': 'adha2',
    '2038-01-18': 'adha3',
    '2038-02-15': 'ashura',
    '2038-04-17': 'milad',
    '2038-08-28': 'meraj',
    '2038-09-15': 'barat',
    '2038-10-26': 'qadr',
    '2038-10-30': 'fitr1',
    '2038-10-31': 'fitr2',
    '2038-11-01': 'fitr3',
    '2039-01-06': 'adha1',
    '2039-01-07': 'adha2',
    '2039-01-08': 'adha3',
    '2039-02-04': 'ashura',
    '2039-04-06': 'milad',
    '2039-08-17': 'meraj',
    '2039-09-04': 'barat',
    '2039-10-15': 'qadr',
    '2039-10-19': 'fitr1',
    '2039-10-20': 'fitr2',
    '2039-10-21': 'fitr3',
    '2039-12-26': 'adha1',
    '2039-12-27': 'adha2',
    '2039-12-28': 'adha3',
    '2040-01-24': 'ashura',
    '2040-03-25': 'milad',
    '2040-08-05': 'meraj',
    '2040-08-23': 'barat',
    '2040-10-03': 'qadr',
    '2040-10-07': 'fitr1',
    '2040-10-08': 'fitr2',
    '2040-10-09': 'fitr3',
    '2040-12-14': 'adha1',
    '2040-12-15': 'adha2',
    '2040-12-16': 'adha3',
};

const Map<String, BdHoliday> _islamicNames = {
  'barat': BdHoliday('Shab-e-Barat', 'শবে বরাত'),
  'fitr1': BdHoliday('Eid-ul-Fitr (Day 1)', 'ঈদুল ফিতর (১ম দিন)'),
  'fitr2': BdHoliday('Eid-ul-Fitr (Day 2)', 'ঈদুল ফিতর (২য় দিন)'),
  'fitr3': BdHoliday('Eid-ul-Fitr (Day 3)', 'ঈদুল ফিতর (৩য় দিন)'),
  'qadr': BdHoliday('Shab-e-Qadr', 'শবে কদর'),
  'adha1': BdHoliday('Eid-ul-Adha (Day 1)', 'ঈদুল আজহা (১ম দিন)'),
  'adha2': BdHoliday('Eid-ul-Adha (Day 2)', 'ঈদুল আজহা (২য় দিন)'),
  'adha3': BdHoliday('Eid-ul-Adha (Day 3)', 'ঈদুল আজহা (৩য় দিন)'),
  'ashura': BdHoliday('Ashura', 'আশুরা'),
  'milad': BdHoliday('Eid-e-Miladunnabi', 'ঈদে মিলাদুন্নবী'),
  'meraj': BdHoliday('Shab-e-Meraj', 'শবে মেরাজ'),
};

/// Returns the holiday on [day], or null if it's not a holiday.
BdHoliday? bdHolidayOn(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  // Fixed Gregorian.
  final fixed = _fixed['${d.month}-${d.day}'];
  if (fixed != null) return fixed;

  // Easter weekend.
  final easterStr = _easter[d.year];
  if (easterStr != null) {
    final p = easterStr.split('-').map(int.parse).toList();
    final easter = DateTime(d.year, p[0], p[1]);
    if (d == easter.subtract(const Duration(days: 2))) {
      return const BdHoliday('Good Friday', 'গুড ফ্রাইডে');
    }
    if (d == easter) {
      return const BdHoliday('Easter Sunday', 'ইস্টার সানডে');
    }
    if (d == easter.add(const Duration(days: 1))) {
      return const BdHoliday('Easter Monday', 'ইস্টার মানডে');
    }
  }

  // Buddha Purnima.
  final bpStr = _buddhaPurnima[d.year];
  if (bpStr != null) {
    final p = bpStr.split('-').map(int.parse).toList();
    if (d.month == p[0] && d.day == p[1]) {
      return const BdHoliday('Buddha Purnima', 'বুদ্ধ পূর্ণিমা');
    }
  }

  // Durga Puja (Dashami + Navami).
  final pujaStr = _durgaPuja[d.year];
  if (pujaStr != null) {
    final p = pujaStr.split('-').map(int.parse).toList();
    final dashami = DateTime(d.year, p[0], p[1]);
    if (d == dashami) {
      return const BdHoliday('Durga Puja (Vijaya Dashami)',
          'দুর্গাপূজা (বিজয়া দশমী)');
    }
    if (d == dashami.subtract(const Duration(days: 1))) {
      return const BdHoliday('Durga Puja (Navami)', 'দুর্গাপূজা (নবমী)');
    }
  }

  // Islamic holidays (precomputed table).
  final ymd = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  final key = _islamicDates[ymd];
  if (key != null) {
    final h = _islamicNames[key];
    if (h != null) return h;
  }

  return null;
}

/// True when [day] is a Bangladesh public holiday.
bool isBdHoliday(DateTime day) => bdHolidayOn(day) != null;

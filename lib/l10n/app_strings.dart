import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// Looks up [key] in the current app language. Must be called from build().
String tr(BuildContext context, String key) {
  final lang = context.watch<SettingsProvider>().language;
  return AppStrings.get(key, lang);
}

/// Simple hand-rolled localization: 'bn' (default) and 'en'.
class AppStrings {
  static const Map<String, Map<String, String>> _values = {
    'en': {
      'tagline': 'Daily Expense Tracker',
      'nav_home': 'Home',
      'nav_add': 'Add',
      'nav_reports': 'Reports',
      'nav_settings': 'Settings',
      'today': 'Today',
      'this_week': 'This week',
      'this_month': 'This month',
      'add_expense': 'Add Expense',
      'edit_expense': 'Edit Expense',
      'amount': 'Amount',
      'amount_hint': '0',
      'category': 'Category',
      'date': 'Date',
      'note': 'Note',
      'note_hint': 'Add a note (optional)',
      'payment_method': 'Payment Method',
      'pm_cash': 'Cash',
      'pm_bkash': 'bKash',
      'pm_card': 'Card',
      'pm_other': 'Other',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'confirm': 'Yes',
      'delete_title': 'Delete expense?',
      'delete_message': 'This expense will be permanently deleted.',
      'search_hint': 'Search by note…',
      'filter_label': 'Category',
      'all': 'All',
      'no_expenses': 'No expenses yet',
      'no_expenses_sub': 'Use the Add tab below to record your first expense.',
      'last_6_months': 'Spending — last 6 months',
      'by_category': 'Spending by category',
      'pick_month': 'Month',
      'no_data': 'No data for this period.',
      'month_total': 'Month total',
      'language': 'Language',
      'theme': 'Theme',
      'dark_mode': 'Dark mode',
      'about': 'About',
      'app_version': 'Version 1.0.0',
      'err_amount_empty': 'Please enter an amount',
      'err_amount_invalid': 'Please enter a valid number',
      'msg_saved': 'Expense added',
      'msg_updated': 'Expense updated',
      'msg_deleted': 'Expense deleted',
      'day_today': 'Today',
      'day_yesterday': 'Yesterday',
      'cat_food': 'Food',
      'cat_transport': 'Transport',
      'cat_shopping': 'Shopping',
      'cat_bills': 'Bills',
      'cat_health': 'Health',
      'cat_entertainment': 'Entertainment',
      'cat_education': 'Education',
      'cat_others': 'Others',
    },
    'bn': {
      'tagline': 'দৈনিক খরচের হিসাব',
      'nav_home': 'হোম',
      'nav_add': 'যোগ করুন',
      'nav_reports': 'রিপোর্ট',
      'nav_settings': 'সেটিংস',
      'today': 'আজ',
      'this_week': 'এই সপ্তাহ',
      'this_month': 'এই মাস',
      'add_expense': 'খরচ যোগ করুন',
      'edit_expense': 'খরচ সম্পাদনা করুন',
      'amount': 'পরিমাণ',
      'amount_hint': '০',
      'category': 'ক্যাটাগরি',
      'date': 'তারিখ',
      'note': 'নোট',
      'note_hint': 'নোট লিখুন (ঐচ্ছিক)',
      'payment_method': 'পেমেন্ট মাধ্যম',
      'pm_cash': 'নগদ',
      'pm_bkash': 'বিকাশ',
      'pm_card': 'কার্ড',
      'pm_other': 'অন্যান্য',
      'save': 'সংরক্ষণ',
      'cancel': 'বাতিল',
      'delete': 'মুছুন',
      'confirm': 'হ্যাঁ',
      'delete_title': 'খরচ মুছে ফেলবেন?',
      'delete_message': 'এই খরচটি স্থায়ীভাবে মুছে যাবে।',
      'search_hint': 'নোট দিয়ে খুঁজুন…',
      'filter_label': 'ক্যাটাগরি',
      'all': 'সব',
      'no_expenses': 'এখনো কোনো খরচ নেই',
      'no_expenses_sub': 'নিচের "যোগ করুন" ট্যাব থেকে প্রথম খরচ লিখুন।',
      'last_6_months': 'শেষ ৬ মাসের খরচ',
      'by_category': 'ক্যাটাগরি অনুযায়ী খরচ',
      'pick_month': 'মাস',
      'no_data': 'এই সময়ের কোনো তথ্য নেই।',
      'month_total': 'মাসের মোট',
      'language': 'ভাষা',
      'theme': 'থিম',
      'dark_mode': 'ডার্ক মোড',
      'about': 'সম্পর্কে',
      'app_version': 'সংস্করণ ১.০.০',
      'err_amount_empty': 'পরিমাণ লিখুন',
      'err_amount_invalid': 'সঠিক সংখ্যা লিখুন',
      'msg_saved': 'খরচ যোগ হয়েছে',
      'msg_updated': 'খরচ হালনাগাদ হয়েছে',
      'msg_deleted': 'খরচ মুছে ফেলা হয়েছে',
      'day_today': 'আজ',
      'day_yesterday': 'গতকাল',
      'cat_food': 'খাবার',
      'cat_transport': 'যাতায়াত',
      'cat_shopping': 'কেনাকাটা',
      'cat_bills': 'বিল',
      'cat_health': 'স্বাস্থ্য',
      'cat_entertainment': 'বিনোদন',
      'cat_education': 'শিক্ষা',
      'cat_others': 'অন্যান্য',
    },
  };

  static String get(String key, String lang) {
    return _values[lang]?[key] ?? _values['en']![key] ?? key;
  }

  static String categoryName(String categoryId, String lang) {
    return get('cat_$categoryId', lang);
  }

  static String paymentName(String method, String lang) {
    return get('pm_$method', lang);
  }
}

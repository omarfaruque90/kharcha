/// Package BA: OCR bill auto-categorization.
///
/// [categorizeShop] maps a shop/merchant name (e.g. OCR text from a receipt)
/// to one of the REAL built-in category ids from lib/models/category.dart:
/// 'food', 'transport', 'shopping', 'bills', 'health', 'pet_food', 'vet',
/// 'entertainment', 'education'.
///
/// The keyword lists mirror [SmsService.guessCategory] so SMS parsing and
/// OCR categorization agree. Returns null when nothing matches — the caller
/// must leave the user's current selection untouched in that case.
///
/// Pure function, no Flutter dependencies: safe to unit-test.
String? categorizeShop(String shopName) {
  final l = ' ${shopName.toLowerCase()} ';
  bool any(List<String> kws) => kws.any(l.contains);

  // BD supershops + general shopping (kept before 'food' so e.g.
  // "Shwapno food court" still lands in shopping).
  if (any(const [
    'supershop',
    'super shop',
    'meena bazar',
    'shwapno',
    'agora',
    'unimart',
    'chaldal',
    'grocery',
    'bazar',
    'market',
    'shop',
    'store',
    'mall',
    'daraz',
    'tailor',
    'salon',
    'boutique',
    'electronics',
  ])) {
    return 'shopping';
  }

  // Restaurants & food outlets.
  if (any(const [
    'restaurant',
    'kacchi',
    'pizza',
    'burger',
    'cafe',
    'coffee',
    'biriyani',
    'biryani',
    'bakery',
    'hotel',
    'dining',
    'canteen',
    'kitchen',
    'food',
  ])) {
    return 'food';
  }

  // Pharmacies / hospitals / diagnostics. 'square' included for
  // Square Pharmaceuticals receipts.
  if (any(const [
    'pharmacy',
    'pharma',
    'square',
    'hospital',
    'doctor',
    'clinic',
    'medicine',
    'diagnostic',
    'dentist',
    'health',
  ])) {
    return 'health';
  }

  // Rides & fuel.
  if (any(const [
    'uber',
    'pathao',
    'bus',
    'cng',
    'rickshaw',
    'taxi',
    'train',
    'metro',
    'launch',
    'fuel',
    'petrol',
    'octane',
    'parking',
  ])) {
    return 'transport';
  }

  // Mobile operators & utility bills.
  if (any(const [
    'grameenphone',
    'grameen phone',
    'robi',
    'banglalink',
    'teletalk',
    'airtel',
    'recharge',
    'topup',
    'top-up',
    'broadband',
    'internet',
    'desco',
    'dpdc',
    'wasa',
    'titas',
    'electricity',
  ])) {
    return 'bills';
  }

  // Pet stores → pet food; vet clinics → vet.
  if (any(const ['pet store', 'pet shop', 'pet food', 'paw', 'purr'])) {
    return 'pet_food';
  }
  if (any(const ['vet', 'veterinary', 'animal hospital'])) {
    return 'vet';
  }

  // No confident match: leave the user's selection alone.
  return null;
}

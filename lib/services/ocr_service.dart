import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// On-device bill/receipt OCR using ML Kit Text Recognition.
/// No network, no API key — everything runs on the phone.
class OcrService {
  OcrService._();

  /// Scans [image] and tries to extract the bill total.
  /// Returns `{'amount': double?, 'rawText': String}`.
  /// Returns null when recognition itself fails.
  static Future<Map<String, dynamic>?> scanBillAmount(XFile image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognized = await recognizer.processImage(inputImage);
      final text = recognized.text;
      if (text.trim().isEmpty) {
        return {'amount': null, 'rawText': ''};
      }
      return {'amount': _extractAmount(text), 'rawText': text};
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  /// Best-effort total extraction from OCR text.
  /// Order: total-keyword lines → currency-prefixed numbers → largest number.
  static double? _extractAmount(String text) {
    final lines = text.split('\n');

    // 1. Lines mentioning the total — take the last number on the line.
    final totalRe = RegExp(
      r'grand\s*total|net\s*amount|amount\s*(payable|due)|balance\s*due|\btotal\b',
      caseSensitive: false,
    );
    for (var i = lines.length - 1; i >= 0; i--) {
      if (totalRe.hasMatch(lines[i])) {
        final amount = _lastNumber(lines[i]);
        if (amount != null) return amount;
      }
    }

    // 2. Currency-prefixed amounts (৳ / Tk / BDT / Rs / টাকা).
    final currencyRe = RegExp(
      r'(?:৳|টাকা|tk\.?|bdt\.?|rs\.?)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    double? best;
    for (final line in lines) {
      for (final m in currencyRe.allMatches(line)) {
        final v = _parseNumber(m.group(1)!);
        if (v != null && (best == null || v > best)) best = v;
      }
    }
    if (best != null) return best;

    // 3. Fallback: the largest plausible number in the text.
    final numRe = RegExp(r'\d[\d,]*\.\d{1,2}|\d[\d,]*');
    for (final line in lines) {
      for (final m in numRe.allMatches(line)) {
        final v = _parseNumber(m.group(0)!);
        // Skip year-like and phone-like numbers.
        if (v != null && v < 10000000 && (best == null || v > best)) {
          best = v;
        }
      }
    }
    return best;
  }

  /// The last (right-most) number on a line — totals are usually at the end.
  static double? _lastNumber(String line) {
    final numRe = RegExp(r'[\d,]+(?:\.\d{1,2})?');
    double? result;
    for (final m in numRe.allMatches(line)) {
      result = _parseNumber(m.group(0)!);
    }
    return result;
  }

  static double? _parseNumber(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    if (v == null || v <= 0) return null;
    return v;
  }
}

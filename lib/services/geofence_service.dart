import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/app_strings.dart';
import 'notification_center.dart';
import 'notification_service.dart';

/// Location reminders (Package X): geofence check service.
///
/// Places are stored as JSON in the 'geofence_places' setting:
/// [{id, name, lat, lng, radius}].
///
/// [check] is the background entry point, called from the periodic
/// background worker. It fires a one-shot reminder when the user enters a
/// saved place's radius and re-arms on exit. Never throws.
class GeofenceService {
  GeofenceService._();

  static const String placesKey = 'geofence_places';
  static const String enabledKey = 'geofence_enabled';
  static const double defaultRadius = 200; // meters

  /// Raw list of places: [{id, name, lat, lng, radius}].
  static Future<List<Map<String, dynamic>>> getPlaces() async {
    try {
      final raw = await DatabaseHelper.instance.getSetting(placesKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePlaces(
      List<Map<String, dynamic>> places) async {
    try {
      await DatabaseHelper.instance
          .setSetting(placesKey, jsonEncode(places));
    } catch (_) {}
  }

  static Future<void> addPlace(String name, double lat, double lng,
      {double radius = defaultRadius}) async {
    final places = await getPlaces();
    places.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'lat': lat,
      'lng': lng,
      'radius': radius,
    });
    await savePlaces(places);
  }

  static Future<void> removePlace(String id) async {
    final places = await getPlaces();
    places.removeWhere((p) => p['id']?.toString() == id);
    await savePlaces(places);
  }

  static Future<bool> isEnabled() async {
    try {
      return await DatabaseHelper.instance.getSetting(enabledKey) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      await DatabaseHelper.instance
          .setSetting(enabledKey, value ? '1' : '0');
    } catch (_) {}
  }

  /// Background entry point: checks the current position against every
  /// saved place. Entry into a radius fires the reminder once; leaving
  /// re-arms the trigger. Never throws.
  static Future<void> check() async {
    try {
      if (!await isEnabled()) return;
      final places = await getPlaces();
      if (places.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 20),
      );
      final lang =
          await DatabaseHelper.instance.getSetting('language') ?? 'bn';
      final today = DateTime.now().toIso8601String().substring(0, 10);
      for (final p in places) {
        final id = p['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final radius = (p['radius'] as num?)?.toDouble() ?? defaultRadius;
        final d = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, lat, lng);
        final inside = d <= radius;
        final key = 'geo_inside_$id';
        final wasInside = prefs.getBool(key) ?? false;
        if (inside && !wasInside) {
          final name = p['name']?.toString() ?? '';
          final title = AppStrings.get('geo_notif_title', lang);
          final body = AppStrings.get('geo_notif_body', lang)
              .replaceAll('{name}', name);
          await NotificationService.showNow(title: title, body: body);
          await NotificationCenter.push(
            title: title,
            body: body,
            type: 'geofence',
            dedupeKey: 'geo_$id:$today',
          );
          await prefs.setBool(key, true);
        } else if (!inside && wasInside) {
          // Left the area: re-arm so the next entry fires again.
          await prefs.setBool(key, false);
        }
      }
    } catch (_) {
      // Best-effort background work; never crash the worker.
    }
  }
}

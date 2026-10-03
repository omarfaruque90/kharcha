import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/app_strings.dart';
import '../services/geofence_service.dart';

/// Location reminders (Package X): manage geofenced places.
///
/// Users save named places; when they enter a place's radius, the
/// background worker fires a "log your spending" reminder.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _places = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await GeofenceService.isEnabled();
      final places = await GeofenceService.getPlaces();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _places = places;
        _loading = false;
      });
    } catch (_) {
      // A storage failure must not leave the spinner on forever.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await GeofenceService.setEnabled(value);
    if (value && mounted) {
      // Fire an immediate check so the user gets feedback right away.
      await GeofenceService.check();
    }
  }

  Future<void> _addCurrentLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (!mounted) return;
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'places_perm_denied'))),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      final name = await _askName();
      if (name == null || name.isEmpty) return;
      await GeofenceService.addPlace(name, pos.latitude, pos.longitude);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'places_loc_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'places_name_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr(ctx, 'places_name_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(tr(ctx, 'save')),
          ),
        ],
      ),
    ).then((value) {
      controller.dispose();
      return value;
    });
  }

  Future<void> _removePlace(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'places_delete_title')),
        content: Text(
          tr(ctx, 'places_delete_body').replaceAll('{name}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await GeofenceService.removePlace(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Index 0 = enable switch, 1 = divider, then the places (or a single
    // empty-state row), then the add-current-location button.
    final total = (_places.isEmpty ? 1 : _places.length) + 3;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'places_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: total,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return SwitchListTile(
                    secondary: const Icon(Icons.location_on),
                    title: Text(tr(context, 'places_enable')),
                    subtitle: Text(tr(context, 'places_enable_sub')),
                    value: _enabled,
                    onChanged: _setEnabled,
                  );
                }
                if (i == 1) return const Divider();
                if (i == total - 1) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _addCurrentLocation,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(tr(context, 'places_add_current')),
                    ),
                  );
                }
                if (_places.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 48),
                    child: Column(
                      children: [
                        const Icon(Icons.place_outlined, size: 56),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'places_empty'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                final p = _places[i - 2];
                return ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(p['name']?.toString() ?? ''),
                  subtitle: Text(
                    tr(context, 'places_radius_m').replaceAll(
                      '{r}',
                      (((p['radius'] as num?)?.toDouble() ??
                                  GeofenceService.defaultRadius))
                              .toStringAsFixed(0),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removePlace(
                      p['id']?.toString() ?? '',
                      p['name']?.toString() ?? '',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:alertu_flutter/camera_page.dart';
import 'package:alertu_flutter/choose_another.dart';

class IsThisYourLocation extends StatefulWidget {
  final double latitude;
  final double longitude;
  final ValueListenable<Position?>? livePositionListenable;

  const IsThisYourLocation({
    super.key,
    required this.latitude,
    required this.longitude,
    this.livePositionListenable,
  });

  @override
  State<IsThisYourLocation> createState() => _IsThisYourLocationState();
}

class _IsThisYourLocationState extends State<IsThisYourLocation> {
  late double _latitude;
  late double _longitude;
  String _addressLabel = 'Finding your current location…';
  Timer? _reverseGeocodeTimer;
  int _reverseGeocodeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _latitude = widget.latitude;
    _longitude = widget.longitude;
    widget.livePositionListenable?.addListener(_handleLivePositionChanged);
    _handleLivePositionChanged();
    _queueReverseGeocode();
  }

  @override
  void dispose() {
    widget.livePositionListenable?.removeListener(_handleLivePositionChanged);
    _reverseGeocodeTimer?.cancel();
    _reverseGeocodeRequestId++;
    super.dispose();
  }

  void _handleLivePositionChanged() {
    final position = widget.livePositionListenable?.value;
    if (position == null || !mounted) return;

    if (position.latitude != _latitude || position.longitude != _longitude) {
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      _queueReverseGeocode();
    }
  }

  void _queueReverseGeocode() {
    _reverseGeocodeTimer?.cancel();
    _reverseGeocodeTimer = Timer(const Duration(milliseconds: 500), () {
      _loadAddressForCoordinates(_latitude, _longitude);
    });
  }

  Future<void> _loadAddressForCoordinates(double latitude, double longitude) async {
    final requestId = ++_reverseGeocodeRequestId;

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
              '?format=jsonv2&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1',
        ),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'AlertU Flutter location confirmation',
        },
      ).timeout(const Duration(seconds: 8));

      if (!mounted || requestId != _reverseGeocodeRequestId) return;
      if (response.statusCode != 200) {
        setState(() => _addressLabel = 'Current address unavailable');
        return;
      }

      final decoded = jsonDecode(response.body);
      final address = decoded is Map && decoded['address'] is Map
          ? Map<String, dynamic>.from(decoded['address'] as Map)
          : <String, dynamic>{};

      final parts = <String>[];
      final barangay = (address['neighbourhood'] ??
          address['suburb'] ??
          address['village'] ??
          address['quarter'])
          ?.toString()
          .trim();
      final city = (address['city'] ??
          address['town'] ??
          address['municipality'] ??
          address['city_district'])
          ?.toString()
          .trim();
      final province = (address['state'] ?? address['province'])
          ?.toString()
          .trim();

      if (barangay != null && barangay.isNotEmpty) parts.add(barangay);
      if (city != null && city.isNotEmpty && !parts.contains(city)) {
        parts.add(city);
      }
      if (province != null && province.isNotEmpty && !parts.contains(province)) {
        parts.add(province);
      }
      parts.add('Philippines');

      setState(() {
        _addressLabel = parts.join(', ');
      });
    } catch (error) {
      if (!mounted || requestId != _reverseGeocodeRequestId) return;
      setState(() => _addressLabel = 'Current address unavailable');
      debugPrint('Reverse geocoding failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor =
    isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final sheetBg =
    isDark ? theme.colorScheme.surfaceContainer : const Color(0xFFF8F6F6);
    final textMain =
    isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
    final textMuted =
    isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);
    final dragHandleColor = isDark
        ? theme.colorScheme.outline.withOpacity(0.4)
        : const Color(0xFFCBD5E1);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.8),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(dragHandleColor),
            const SizedBox(height: 24),
            Icon(Icons.location_on, size: 64, color: primaryColor),
            const SizedBox(height: 16),
            Text(
              'Is this your location?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: textMain,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _addressLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.45,
                color: textMain.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your precise location helps emergency responders locate you quickly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
            const SizedBox(height: 32),
            _buildButtons(context, primaryColor, isDark),
            const SizedBox(height: 24),
            Text(
              '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle(Color handleColor) => Container(
    width: 48,
    height: 6,
    decoration: BoxDecoration(
      color: handleColor,
      borderRadius: BorderRadius.circular(9999),
    ),
  );

  Widget _buildButtons(BuildContext context, Color primaryColor, bool isDark) {
    final outlinedBorderColor =
    isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    final secondaryTextColor =
    isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CameraPage(
                    latitude: _latitude,
                    longitude: _longitude,
                  ),
                ),
              );
            },
            child: const Text(
              'Yes, this is my location',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: outlinedBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChooseAnotherPage(
                    initialLocation: LatLng(_latitude, _longitude),
                    onLocationConfirmed: (newLocation) {
                      debugPrint(
                        'Manual selection locked on MapLibre map: '
                            '${newLocation.latitude}, ${newLocation.longitude}',
                      );
                    },
                  ),
                ),
              );
            },
            child: Text(
              'No, choose another location',
              style: TextStyle(color: secondaryTextColor),
            ),
          ),
        ),
      ],
    );
  }
}


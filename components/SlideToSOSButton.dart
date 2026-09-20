import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../services/socket.dart';
import '../services/userlocation_tracker.dart';
import '../services/SOSNotif_service.dart';
import '../services/api_service.dart';

/// Call this function from any screen to present the responsive Emergency SOS Bottom Sheet with Dark Mode support
void showEmergencySosModal({
  required BuildContext context,
  String citizenId = '',
  String submitterName = '',
  String email = '',
  String phone = '',
  List<Map<String, String>> emergencyContacts = const [],
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: isDark ? Colors.black.withOpacity(0.7) : Colors.black.withOpacity(0.5),
    builder: (ctx) => EmergencySosModalWrapper(
      citizenId: citizenId,
      submitterName: submitterName,
      email: email,
      phone: phone,
      emergencyContacts: emergencyContacts,
    ),
  );
}

class EmergencySosModalWrapper extends StatefulWidget {
  final String citizenId;
  final String submitterName;
  final String email;
  final String phone;
  final List<Map<String, String>> emergencyContacts;

  const EmergencySosModalWrapper({
    super.key,
    this.citizenId = '',
    this.submitterName = '',
    this.email = '',
    this.phone = '',
    this.emergencyContacts = const [],
  });

  @override
  State<EmergencySosModalWrapper> createState() => _EmergencySosModalWrapperState();
}

class _EmergencySosModalWrapperState extends State<EmergencySosModalWrapper> {
  bool _isLoading = false;

  void _setLoadingState(bool loading) {
    if (mounted) {
      setState(() {
        _isLoading = loading;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dark Mode Palette
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final handleColor = isDark ? const Color(0xFF475569) : Colors.grey.shade300;
    final iconBg = isDark ? const Color(0xFF450A0A) : Colors.red.shade50;
    final iconColor = isDark ? const Color(0xFFF87171) : Colors.red.shade700;
    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600;

    return PopScope(
      canPop: !_isLoading,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black : Colors.black12,
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: handleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: iconColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Emergency Dispatch",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Slide to broadcast live location to emergency responders.",
                            style: TextStyle(
                              fontSize: 12,
                              color: subtitleColor,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SlideToSOSButton(
                  citizenId: widget.citizenId,
                  submitterName: widget.submitterName,
                  email: widget.email,
                  phone: widget.phone,
                  emergencyContacts: widget.emergencyContacts,
                  onLoadingStateChanged: _setLoadingState,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SlideToSOSButton extends StatefulWidget {
  final String citizenId;
  final String submitterName;
  final String email;
  final String phone;
  final List<Map<String, String>> emergencyContacts;
  final ValueChanged<bool>? onLoadingStateChanged;

  const SlideToSOSButton({
    super.key,
    this.citizenId = '',
    this.submitterName = '',
    this.email = '',
    this.phone = '',
    this.emergencyContacts = const [],
    this.onLoadingStateChanged,
  });

  @override
  State<SlideToSOSButton> createState() => _SlideToSOSButtonState();
}

class _SlideToSOSButtonState extends State<SlideToSOSButton> {
  double _dragPosition = 0.0;
  static const double _buttonHeight = 60.0;
  static const double _thumbSize = 52.0;

  bool _isLoading = false;
  bool _isSuccess = false;

  /// Robust location fetcher: Attempts high-accuracy fix, falls back to last known position
  Future<Position?> _getReliableLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return await Geolocator.getLastKnownPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return await Geolocator.getLastKnownPosition();
      }

      if (permission == LocationPermission.deniedForever) {
        return await Geolocator.getLastKnownPosition();
      }

      // 1. Try high accuracy with timeout
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } catch (_) {
        // 2. Fallback to quick low accuracy
        try {
          return await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 2),
            ),
          );
        } catch (_) {
          // 3. Fallback to cached device location
          return await Geolocator.getLastKnownPosition();
        }
      }
    } catch (e) {
      debugPrint("❌ Error fetching location: $e");
      return await Geolocator.getLastKnownPosition();
    }
  }

  /// Comprehensive profile retriever checking multiple collections & field name variations
  Future<Map<String, dynamic>> _fetchFullUserProfile(String uid) async {
    Map<String, dynamic> resolvedData = {
      'phone': '',
      'name': '',
      'email': '',
      'contacts': <Map<String, dynamic>>[],
    };

    if (uid.isEmpty) return resolvedData;

    final collectionsToTry = ['users', 'citizens', 'profiles'];

    for (final col in collectionsToTry) {
      try {
        final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;

          // Phone Resolution
          if ((resolvedData['phone'] as String).isEmpty) {
            final rawPhone = data['phone'] ??
                data['phoneNumber'] ??
                data['contactNumber'] ??
                data['mobile'] ??
                data['contact_number'];
            if (rawPhone != null && rawPhone.toString().trim().isNotEmpty) {
              resolvedData['phone'] = rawPhone.toString().trim();
            }
          }

          // Name Resolution
          if ((resolvedData['name'] as String).isEmpty) {
            final rawName = data['fullName'] ??
                data['displayName'] ??
                data['name'] ??
                data['submitterName'] ??
                data['citizenName'];
            if (rawName != null && rawName.toString().trim().isNotEmpty) {
              resolvedData['name'] = rawName.toString().trim();
            }
          }

          // Email Resolution
          if ((resolvedData['email'] as String).isEmpty) {
            final rawEmail = data['email'] ?? data['citizenEmail'];
            if (rawEmail != null && rawEmail.toString().trim().isNotEmpty) {
              resolvedData['email'] = rawEmail.toString().trim();
            }
          }

          // Contacts Resolution
          if ((resolvedData['contacts'] as List).isEmpty) {
            final rawContacts = data['emergencyContacts'] ??
                data['contacts'] ??
                data['emergency_contacts'] ??
                data['emergencyContactsList'];

            if (rawContacts is List && rawContacts.isNotEmpty) {
              List<Map<String, dynamic>> parsedList = [];
              for (var item in rawContacts) {
                if (item is Map) {
                  parsedList.add({
                    'name': (item['name'] ?? item['contactName'] ?? 'Emergency Contact').toString(),
                    'phone': (item['phone'] ?? item['phoneNumber'] ?? item['number'] ?? item['mobile'] ?? '').toString(),
                    'relationship': (item['relationship'] ?? item['relation'] ?? 'Contact').toString(),
                  });
                } else if (item is String) {
                  parsedList.add({'name': 'Contact', 'phone': item, 'relationship': 'Emergency Contact'});
                }
              }
              resolvedData['contacts'] = parsedList;
            }
          }
        }
      } catch (e) {
        debugPrint("⚠️ Failed reading $col for UID $uid: $e");
      }
    }

    return resolvedData;
  }

  Future<void> _handleSOSTrigger(BuildContext context) async {
    if (_isLoading || _isSuccess) return;

    setState(() {
      _isLoading = true;
    });
    widget.onLoadingStateChanged?.call(true);

    HapticFeedback.heavyImpact();

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final rawCitizenUid = currentUser?.uid ?? '';

      // ⚡ RUN ALL HEAVY FETCHES IN PARALLEL ⚡
      final results = await Future.wait([
        _getReliableLocation(),
        _fetchFullUserProfile(rawCitizenUid),
        ApiService.baseUrl == null || ApiService.baseUrl!.isEmpty
            ? ApiService.initBackend()
            : Future.value(null),
      ]);

      Position? position = results[0] as Position?;
      Map<String, dynamic> dbProfile = results[1] as Map<String, dynamic>;

      // --- 1. RESOLVE LOCATION GUARANTEED ---
      double latitude = position?.latitude ?? 0.0;
      double longitude = position?.longitude ?? 0.0;
      double altitude = position?.altitude ?? 0.0;
      double accuracy = position?.accuracy ?? 0.0;

      // --- 2. RESOLVE PHONE GUARANTEED ---
      String resolvedPhone = widget.phone.trim();
      if (resolvedPhone.isEmpty || resolvedPhone == 'N/A') {
        resolvedPhone = (dbProfile['phone'] as String).trim();
      }
      if (resolvedPhone.isEmpty || resolvedPhone == 'N/A') {
        resolvedPhone = currentUser?.phoneNumber?.trim() ?? '';
      }
      if (resolvedPhone.isEmpty) {
        resolvedPhone = 'N/A';
      }

      // --- 3. RESOLVE EMERGENCY CONTACTS GUARANTEED ---
      List<Map<String, dynamic>> resolvedContacts = widget.emergencyContacts
          .map((c) => Map<String, dynamic>.from(c))
          .toList();

      if (resolvedContacts.isEmpty) {
        resolvedContacts = List<Map<String, dynamic>>.from(dbProfile['contacts'] ?? []);
      }

      // --- 4. RESOLVE NAME & EMAIL GUARANTEED ---
      String resolvedName = widget.submitterName.trim();
      if (resolvedName.isEmpty) {
        resolvedName = (dbProfile['name'] as String).trim();
      }
      if (resolvedName.isEmpty) {
        resolvedName = currentUser?.displayName ?? 'Emergency Citizen';
      }

      String resolvedEmail = widget.email.trim();
      if (resolvedEmail.isEmpty) {
        resolvedEmail = (dbProfile['email'] as String).trim();
      }
      if (resolvedEmail.isEmpty) {
        resolvedEmail = currentUser?.email ?? 'N/A';
      }

      final String canonicalSosId = rawCitizenUid.startsWith('sos_')
          ? rawCitizenUid
          : 'sos_$rawCitizenUid';

      final String primaryCitizenID = widget.citizenId.trim().isNotEmpty
          ? widget.citizenId.trim()
          : rawCitizenUid;

      final idToken = await currentUser?.getIdToken();

      final Map<String, dynamic> gisLocation = {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'accuracy': accuracy,
        'speed': position?.speed ?? 0,
        'heading': position?.heading ?? 0,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      Map<String, dynamic> sosPayload = {
        'sosId': canonicalSosId,
        'id': canonicalSosId,
        'targetRoom': canonicalSosId,
        'citizenUid': rawCitizenUid,
        'citizenID': primaryCitizenID,
        'citizenName': resolvedName,
        'submitterName': resolvedName,
        'citizenEmail': resolvedEmail,
        'submitterEmail': resolvedEmail,
        'email': resolvedEmail,
        'citizenPhone': resolvedPhone,
        'submitterPhone': resolvedPhone,
        'phone': resolvedPhone,
        'alertType': 'GENERAL_EMERGENCY',
        'status': 'ACTIVE',
        'isActive': true,
        'closedAt': null,
        'isNewSession': true,
        'gisLocation': gisLocation,
        'latitude': latitude,
        'longitude': longitude,
        'emergencyContacts': resolvedContacts,
        'sosDetails': 'Emergency SOS Triggered via Mobile App',
        'triggeredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1. Write snapshot strictly to sos_alerts
      await FirebaseFirestore.instance
          .collection('sos_alerts')
          .doc(canonicalSosId)
          .set(sosPayload, SetOptions(merge: true));

      // 2. Dispatch alert via Express REST Endpoint
      if (ApiService.baseUrl != null && ApiService.baseUrl!.isNotEmpty) {
        final String targetUrl = '${ApiService.baseUrl}/sos/trigger';
        await http.post(
          Uri.parse(targetUrl),
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'sosId': canonicalSosId,
            'citizenID': primaryCitizenID,
            'citizenUid': rawCitizenUid,
            'phone': resolvedPhone,
            'submitterPhone': resolvedPhone,
            'latitude': latitude,
            'longitude': longitude,
            'altitude': altitude,
            'accuracy': accuracy,
            'alertType': 'GENERAL_EMERGENCY',
            'emergencyContacts': resolvedContacts,
            'note': 'Emergency SOS Triggered via Mobile App',
          }),
        );
      }

      // 3. Emit real-time Socket event
      await SocketService.ensureConnected();
      await SocketService.triggerSOSAlert({
        ...sosPayload,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // 4. Start background GPS tracking
      await UserLocationTracker.startTracking(sosId: canonicalSosId);

      // 5. Local Notification
      await SOSNotifService.showSOSNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🚨 Emergency SOS Dispatched',
        body: 'Your active GPS location is being streamed to emergency responders.',
        payload: canonicalSosId,
      );

      // UI Success Feedback
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
        widget.onLoadingStateChanged?.call(false);

        HapticFeedback.mediumImpact();

        await Future.delayed(const Duration(milliseconds: 1200));

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚨 Emergency SOS Signal Sent! Dispatchers Notified.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Failed to execute SOS trigger: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dragPosition = 0.0;
        });
        widget.onLoadingStateChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dark Mode color options for the Slider
    final trackIdleBg = isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);
    final trackLoadingBg = isDark ? const Color(0xFF7F1D1D) : Colors.red.shade50;
    final trackSuccessBg = isDark ? const Color(0xFF064E3B) : Colors.green.shade50;

    final borderIdle = isDark ? const Color(0xFF991B1B) : Colors.red.shade200;
    final borderLoading = isDark ? const Color(0xFFDC2626) : Colors.red.shade400;
    final borderSuccess = isDark ? const Color(0xFF059669) : Colors.green.shade400;

    final fillIdleBg = isDark ? const Color(0xFF991B1B).withOpacity(0.5) : Colors.red.shade100.withOpacity(0.8);
    final fillSuccessBg = isDark ? const Color(0xFF047857).withOpacity(0.5) : Colors.green.shade100;

    final textIdle = isDark ? const Color(0xFFFCA5A5) : Colors.red.shade700;
    final textLoading = isDark ? const Color(0xFFFECACA) : Colors.red.shade800;
    final textSuccess = isDark ? const Color(0xFF6EE7B7) : Colors.green.shade800;

    final successIconColor = isDark ? const Color(0xFF34D399) : Colors.green.shade700;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - _thumbSize - 8.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _buttonHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: _isSuccess
                ? trackSuccessBg
                : (_isLoading ? trackLoadingBg : trackIdleBg),
            borderRadius: BorderRadius.circular(_buttonHeight / 2),
            border: Border.all(
              color: _isSuccess
                  ? borderSuccess
                  : (_isLoading ? borderLoading : borderIdle),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _isSuccess ? constraints.maxWidth : _dragPosition + _thumbSize,
                height: _buttonHeight,
                decoration: BoxDecoration(
                  color: _isSuccess ? fillSuccessBg : fillIdleBg,
                  borderRadius: BorderRadius.circular(_buttonHeight / 2),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isSuccess
                      ? Row(
                    key: const ValueKey('success'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: successIconColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "ALERT DISPATCHED!",
                        style: TextStyle(
                          color: textSuccess,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  )
                      : Text(
                    _isLoading ? "LOCATING GPS & DISPATCHING..." : "SLIDE FOR EMERGENCY SOS",
                    key: ValueKey(_isLoading ? 'loading' : 'idle'),
                    style: TextStyle(
                      color: _isLoading ? textLoading : textIdle,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _isSuccess ? (constraints.maxWidth - _thumbSize - 4.0) : (4.0 + _dragPosition),
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_isLoading || _isSuccess) return;
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0) _dragPosition = 0;
                      if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isLoading || _isSuccess) return;

                    if (_dragPosition >= maxDrag * 0.85) {
                      setState(() {
                        _dragPosition = maxDrag;
                      });
                      _handleSOSTrigger(context);
                    } else {
                      setState(() {
                        _dragPosition = 0.0;
                      });
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: _isSuccess
                          ? (isDark ? const Color(0xFF059669) : Colors.green.shade600)
                          : (_isLoading ? (isDark ? const Color(0xFFDC2626) : Colors.red.shade600) : Colors.redAccent),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isSuccess ? Colors.green : Colors.red).withOpacity(isDark ? 0.5 : 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                          : Icon(
                        _isSuccess ? Icons.check : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
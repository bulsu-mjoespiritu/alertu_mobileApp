import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'socket.dart';

class UserLocationTracker {
  static StreamSubscription<Position>? _positionStreamSubscription;
  static bool _isTracking = false;

  // Track active SOS session ID
  static String? activeSosId;

  // Cached user telemetry metadata
  static Map<String, dynamic>? _cachedUserData;

  /// Returns whether active background location tracking is running
  static bool get isTracking => _isTracking;

  /// Ensures key follows standard single-document format (`sos_{uid}`)
  static String _formatSosDocKey(String rawId) {
    final String clean = rawId.trim();
    if (clean.isEmpty) return '';
    return clean.startsWith('sos_') ? clean : 'sos_$clean';
  }

  /// Starts listening to device location updates and streams them into Firestore & Socket
  static Future<void> startTracking({String? sosId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ UserLocationTracker: Cannot start tracking. No authenticated user found.');
      return;
    }

    await _fetchCitizenDetails(user);

    // 🔑 CANONICAL KEY: Strict fallback to user.uid
    final String resolvedId = (sosId != null && sosId.isNotEmpty) ? sosId : user.uid;
    activeSosId = _formatSosDocKey(resolvedId);

    if (_isTracking) return;

    // Verify Location Service availability
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('⚠️ UserLocationTracker: Location services are disabled.');
      return;
    }

    // Request & Verify Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ UserLocationTracker: Location permissions are denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('⚠️ UserLocationTracker: Location permissions are permanently denied.');
      return;
    }

    _isTracking = true;
    debugPrint('🛰️ UserLocationTracker: Starting real-time location stream for docKey=$activeSosId');

    // Send immediate initial position fix
    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _updateFirestoreAndSocketLocation(user.uid, initialPosition);
      debugPrint('📍 Immediate SOS initial location published.');
    } catch (e) {
      debugPrint('⚠️ Could not fetch immediate initial position: $e');
    }

    // Configure Platform Location Settings
    LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        forceLocationManager: true,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) async {
        await _updateFirestoreAndSocketLocation(user.uid, position);
      },
      onError: (error) {
        debugPrint('❌ UserLocationTracker Stream Error: $error');
      },
    );
  }

  /// Sets or clears active SOS session ID dynamically
  static void setActiveSosId(String? sosId) {
    if (sosId == null || sosId.isEmpty) {
      activeSosId = null;
    } else {
      activeSosId = _formatSosDocKey(sosId);
    }
  }

  /// Stops tracking location and cancels active stream listener
  static Future<void> stopTracking() async {
    if (_positionStreamSubscription != null) {
      await _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
    }
    _cachedUserData = null;
    activeSosId = null;
    _isTracking = false;
    debugPrint('🛑 UserLocationTracker: Location tracking stopped.');
  }

  /// Fetches Submitter info, Citizen ID, and Emergency Contacts from Firestore.
  static Future<void> _fetchCitizenDetails(User user) async {
    String name = (user.displayName != null && user.displayName!.trim().isNotEmpty)
        ? user.displayName!
        : "Citizen User";
    String email = user.email ?? "No email provided";
    String phone = user.phoneNumber ?? "Not Provided";

    String citizenID = user.uid;
    List<Map<String, dynamic>> emergencyContacts = [];

    try {
      final docRef = FirebaseFirestore.instance.collection('citizens').doc(user.uid);
      final doc = await docRef.get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        final docName = data['fullName'] ?? data['name'] ?? data['displayName'];
        if (docName != null && docName.toString().trim().isNotEmpty) {
          name = docName.toString().trim();
        }

        final docEmail = data['email'];
        if (docEmail != null && docEmail.toString().trim().isNotEmpty) {
          email = docEmail.toString().trim();
        }

        final docPhone = data['phoneNumber'] ?? data['phone'] ?? data['contactNumber'];
        if (docPhone != null && docPhone.toString().trim().isNotEmpty) {
          phone = docPhone.toString().trim();
        }

        final docCitizenID = data['citizenID'] ?? data['citizenId'] ?? data['cid'];
        if (docCitizenID != null && docCitizenID.toString().trim().isNotEmpty) {
          citizenID = docCitizenID.toString().trim();
        }

        if (data['emergencyContacts'] != null && data['emergencyContacts'] is List) {
          final List rawContacts = data['emergencyContacts'] as List;
          for (final item in rawContacts) {
            if (item is Map) {
              emergencyContacts.add({
                'name': item['name'] ?? item['fullName'] ?? 'Unknown',
                'phone': item['phone'] ?? item['phoneNumber'] ?? item['contactNumber'] ?? 'Not Provided',
                'relation': item['relation'] ?? item['relationship'] ?? 'Contact',
              });
            }
          }
        }
      } else {
        final defaultProfile = {
          'uid': user.uid,
          'fullName': name,
          'email': email,
          'phoneNumber': phone,
          'citizenID': citizenID,
          'createdAt': FieldValue.serverTimestamp(),
          'emergencyContacts': [],
        };
        await docRef.set(defaultProfile, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('⚠️ UserLocationTracker: Error fetching citizen profile: $e');
    }

    _cachedUserData = {
      'submitterName': name,
      'submitterEmail': email,
      'submitterPhone': phone,
      'citizenID': citizenID,
      'emergencyContacts': emergencyContacts,
    };
  }

  /// Writes position strictly to `sos_alerts` & emits Socket event
  static Future<void> _updateFirestoreAndSocketLocation(String uid, Position position) async {
    final String targetDocId = activeSosId ?? _formatSosDocKey(uid);

    final Map<String, dynamic> gisLocation = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'heading': position.heading,
      'speed': position.speed,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      final Map<String, dynamic> payload = {
        'uid': uid,
        'citizenUid': uid,
        'citizenID': _cachedUserData?['citizenID'] ?? uid,
        'sosId': targetDocId,
        'id': targetDocId,
        'targetRoom': targetDocId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'accuracy': position.accuracy,
        'heading': position.heading,
        'speed': position.speed,
        'gisLocation': gisLocation,
        'status': 'ACTIVE',            // Ensure active status on updates
        'isActive': true,              // Keep active flag alive
        'closedAt': null,              // Clear closed status
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': DateTime.now().toIso8601String(),
        'isOnline': true,
        'submitterName': _cachedUserData?['submitterName'] ?? 'Citizen User',
        'submitterEmail': _cachedUserData?['submitterEmail'] ?? 'No email provided',
        'submitterPhone': _cachedUserData?['submitterPhone'] ?? 'Not Provided',
        'emergencyContacts': _cachedUserData?['emergencyContacts'] ?? [],
      };

      // 1. Single target write: ONLY `sos_alerts`
      await FirebaseFirestore.instance
          .collection('sos_alerts')
          .doc(targetDocId)
          .set(payload, SetOptions(merge: true));

      // 2. Location log subcollection under `sos_alerts`
      await FirebaseFirestore.instance
          .collection('sos_alerts')
          .doc(targetDocId)
          .collection('location_logs')
          .add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 3. Emit real-time Socket.IO event
      SocketService.updateSOSLocation(
        sosId: targetDocId,
        gisLocation: gisLocation,
        citizenUid: uid,
      );

      debugPrint('📍 Live location logged strictly to sos_alerts/[$targetDocId]: [${position.latitude}, ${position.longitude}]');
    } catch (e) {
      debugPrint('❌ UserLocationTracker Location Update Error: $e');
    }
  }
}
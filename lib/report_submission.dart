import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nominatim/flutter_nominatim.dart' hide LatLng;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'confirmation_subpage.dart';
import 'services/api_service.dart';
import 'choose_another.dart';
import 'package:alertu_flutter/user_provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as libre;

class ReportSubmissionPage extends ConsumerStatefulWidget {
  final String? localMediaPath;
  final String? mediaFileName;
  final double latitude;
  final double longitude;

  const ReportSubmissionPage({
    super.key,
    this.localMediaPath,
    this.mediaFileName,
    required this.latitude,
    required this.longitude,
  });

  @override
  ConsumerState<ReportSubmissionPage> createState() => _ReportSubmissionPageState();
}

class _ReportSubmissionPageState extends ConsumerState<ReportSubmissionPage> {
  libre.MapLibreMapController? _reportMapController;

  final Nominatim _nominatim = Nominatim.instance;

  // 📅 Date & Time (Display Only)
  late final DateTime _selectedDateTime;
  late final String _currentDateTimeFormatted;

  // 🛰️ Geographic parameters
  late double _currentLatitude;
  late double _currentLongitude;
  String _currentAddress = "Loading location details...";

  String _selectedIncident = 'Fire';
  String _selectedSeverity = 'Low';
  String _selectedHazard = 'None';

  final TextEditingController _customIncidentController = TextEditingController();
  final TextEditingController _customHazardController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // 🎙️ Voice Recorder
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingAudio = false;
  String? _localAudioPath;
  Timer? _audioTimer;
  int _audioSeconds = 0;

  bool _isSubmitting = false;
  String _submitStatusText = 'Submitting...';

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
    _currentDateTimeFormatted = DateFormat('MMMM dd, yyyy • hh:mm a').format(_selectedDateTime);

    _currentLatitude = widget.latitude;
    _currentLongitude = widget.longitude;
    _syncNominatimAddress(_currentLatitude, _currentLongitude);
  }

  /// Safe local random string generator
  String _generateRandomId([int length = 10]) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Fallback client-side distance calculation in meters between two coordinates
  double _calculateHaversineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    if (lat1.isNaN || lon1.isNaN || lat2.isNaN || lon2.isNaN) return double.infinity;

    const double earthRadiusMeters = 6371000;
    final double radLat1 = _degreesToRadians(lat1);
    final double radLat2 = _degreesToRadians(lat2);
    final double deltaLat = _degreesToRadians(lat2 - lat1);
    final double deltaLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(radLat1) * cos(radLat2) * sin(deltaLon / 2) * sin(deltaLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Hybrid Duplicate Check: First calls ApiService backend, falls back to direct Firestore query if offline
  Future<Map<String, dynamic>> _checkIsDuplicate(
      double lat,
      double lng,
      String incidentType, {
        double maxDistanceMeters = 500,
      }) async {
    try {
      final apiResult = await ApiService.checkDuplicateReport(
        latitude: lat,
        longitude: lng,
        incidentType: incidentType,
      );

      if (apiResult != null && apiResult.containsKey('isDuplicate')) {
        return {
          'isDuplicate': apiResult['isDuplicate'] == true,
          'parentReportId': apiResult['parentReportId'] ?? apiResult['parentId'],
          'distance': apiResult['distance'],
        };
      }
    } catch (apiErr) {
      debugPrint('⚠️ ApiService duplicate check failed, using client fallback: $apiErr');
    }

    try {
      final String targetType = incidentType.trim().toLowerCase();

      final querySnapshot = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('submittedAt', descending: true)
          .limit(50)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return {'isDuplicate': false, 'parentReportId': null};
      }

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final String activeType = (data['incidentType'] ?? data['hazard'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (targetType.isNotEmpty && activeType.isNotEmpty && targetType != activeType) {
          continue;
        }

        double activeLat = double.nan;
        double activeLng = double.nan;

        if (data['latitude'] != null && data['longitude'] != null) {
          activeLat = (data['latitude'] as num).toDouble();
          activeLng = (data['longitude'] as num).toDouble();
        } else if (data['location'] is Map) {
          final loc = data['location'] as Map;
          if (loc['latitude'] != null && loc['longitude'] != null) {
            activeLat = (loc['latitude'] as num).toDouble();
            activeLng = (loc['longitude'] as num).toDouble();
          }
        }

        if (activeLat.isNaN || activeLng.isNaN) continue;

        final double distanceMeters = _calculateHaversineDistanceMeters(
          lat,
          lng,
          activeLat,
          activeLng,
        );

        if (distanceMeters <= maxDistanceMeters) {
          final String parentId = (data['reportId'] ?? data['reportID'] ?? data['id'] ?? doc.id).toString();
          debugPrint('🚨 Duplicate report detected! Parent ID: $parentId ($distanceMeters m away)');
          return {
            'isDuplicate': true,
            'parentReportId': parentId,
            'distance': distanceMeters,
          };
        }
      }

      return {'isDuplicate': false, 'parentReportId': null};
    } catch (err) {
      debugPrint('⚠️ Client duplicate fallback error: $err');
      return {'isDuplicate': false, 'parentReportId': null};
    }
  }

  Future<Map<String, String>> _fetchReporterDetails() async {
    final userProfile = ref.read(userProfileProvider);
    final firebaseUser = FirebaseAuth.instance.currentUser;

    String name = "";
    String email = "";
    String phone = "";
    String citizenID = "";

    if (firebaseUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('citizens')
            .doc(firebaseUser.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          name = data['fullName'] ?? data['name'] ?? data['displayName'] ?? "";
          email = data['email'] ?? "";
          phone = data['phoneNumber'] ?? data['phone'] ?? data['contactNumber'] ?? "";
          citizenID = data['citizenID'] ?? data['citizenId'] ?? firebaseUser.uid;
        }
      } catch (e) {
        debugPrint("Error fetching user document from Firestore: $e");
      }
    }

    if (name.isEmpty) {
      name = userProfile['name']?.toString() ??
          userProfile['displayName']?.toString() ??
          userProfile['fullName']?.toString() ??
          "";
    }
    if (email.isEmpty) {
      email = userProfile['email']?.toString() ?? "";
    }
    if (phone.isEmpty) {
      phone = userProfile['phoneNumber']?.toString() ??
          userProfile['phone']?.toString() ??
          userProfile['contactNumber']?.toString() ??
          "";
    }

    if (name.isEmpty) name = firebaseUser?.displayName ?? "Anonymous Citizen";
    if (email.isEmpty) email = firebaseUser?.email ?? "No email provided";
    if (phone.isEmpty) phone = firebaseUser?.phoneNumber ?? "Not Provided";
    if (citizenID.isEmpty) citizenID = firebaseUser?.uid ?? "CID00000000";

    return {
      'name': name.trim().isEmpty ? 'Anonymous Citizen' : name.trim(),
      'email': email.trim().isEmpty ? 'No email provided' : email.trim(),
      'phone': phone.trim().isEmpty ? 'Not Provided' : phone.trim(),
      'citizenID': citizenID,
    };
  }

  @override
  void didUpdateWidget(covariant ReportSubmissionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude || oldWidget.longitude != widget.longitude) {
      setState(() {
        _currentLatitude = widget.latitude;
        _currentLongitude = widget.longitude;
      });
    }
  }

  Future<void> _syncNominatimAddress(double lat, double lon) async {
    try {
      final Place place = await _nominatim.getAddressFromLatLng(lat, lon);
      if (mounted) {
        setState(() {
          _currentAddress = place.displayName ?? "Selected Location";
        });
      }
    } catch (e) {
      debugPrint("Address lookup error: $e");
      if (mounted) {
        setState(() {
          _currentAddress = "Coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}";
        });
      }
    }
  }

  @override
  void dispose() {
    _customIncidentController.dispose();
    _customHazardController.dispose();
    _notesController.dispose();
    _audioRecorder.dispose();
    _audioTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleAudioRecording() async {
    if (_isSubmitting) return; // Disallow voice note interactions during submission
    // If we already have a finished voice note, block recording new audio until deleted
    if (_localAudioPath != null && !_isRecordingAudio) return;

    if (_isRecordingAudio) {
      await _stopAudioRecording();
    } else {
      await _startAudioRecording();
    }
  }

  Future<void> _startAudioRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final String path = p.join(directory.path, 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a');

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );

        setState(() {
          _isRecordingAudio = true;
          _audioSeconds = 0;
          _localAudioPath = null; // Keep null until recording finishes
        });

        _audioTimer?.cancel();
        _audioTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _audioSeconds++;
          });
          if (_audioSeconds >= 120) {
            _stopAudioRecording();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied.')),
        );
      }
    } catch (e) {
      debugPrint('Failed to start recording: $e');
    }
  }

  Future<void> _stopAudioRecording() async {
    _audioTimer?.cancel();

    try {
      final finalPath = await _audioRecorder.stop();
      setState(() {
        _isRecordingAudio = false;
        _localAudioPath = finalPath ?? _localAudioPath;
      });
    } catch (e) {
      debugPrint("Error finalizing audio recording: $e");
      if (mounted) {
        setState(() {
          _isRecordingAudio = false;
        });
      }
    }
  }

  void _deleteAudioNote() {
    if (_isSubmitting) return; // Disallow deleting audio during submission
    setState(() {
      _localAudioPath = null;
      _audioSeconds = 0;
    });
  }

  Future<void> _onChangeLocationAndRetake() async {
    if (_isSubmitting) return; // Lock changing location while submitting
    FocusScope.of(context).unfocus();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChooseAnotherPage(
          initialLocation: libre.LatLng(_currentLatitude, _currentLongitude),
          onLocationConfirmed: (selectedCoords) {
            setState(() {
              _currentLatitude = selectedCoords.latitude;
              _currentLongitude = selectedCoords.longitude;
              _currentAddress = "Updating location...";
            });
            _syncNominatimAddress(selectedCoords.latitude, selectedCoords.longitude);
          },
        ),
      ),
    );
  }

  Future<void> _saveDirectlyToFirestore(String docId, Map<String, dynamic> payload, bool isDuplicate) async {
    try {
      final String targetCollection = isDuplicate ? 'duplicate_reports' : 'reports';
      await FirebaseFirestore.instance.collection(targetCollection).doc(docId).set({
        ...payload,
        'id': docId,
        'reportId': docId,
        'reportID': docId,
        'submittedAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Saved report directly to Firestore collection: $targetCollection');
    } catch (e) {
      debugPrint('⚠️ Direct Firestore save failed: $e');
    }
  }

  Future<void> _submitFinalReport() async {
    if (_isSubmitting) return;

    if (_isRecordingAudio) {
      await _stopAudioRecording();
    }

    setState(() {
      _isSubmitting = true;
      _submitStatusText = 'Uploading media files...';
    });

    try {
      String? cloudMediaUrl;
      String? cloudAudioUrl;

      // 1. Upload Photo/Video to Cloud on Submit
      if (widget.localMediaPath != null && widget.localMediaPath!.isNotEmpty) {
        final file = File(widget.localMediaPath!);
        if (file.existsSync()) {
          setState(() => _submitStatusText = 'Uploading media to cloud...');
          cloudMediaUrl = await ApiService.uploadMediaToB2(widget.localMediaPath!);
        }
      }

      // 2. Upload Voice Note to Cloud on Submit
      if (_localAudioPath != null && _localAudioPath!.isNotEmpty) {
        final audioFile = File(_localAudioPath!);
        if (audioFile.existsSync()) {
          setState(() => _submitStatusText = 'Uploading voice note...');
          cloudAudioUrl = await ApiService.uploadMediaToB2(_localAudioPath!);
        }
      }

      setState(() => _submitStatusText = 'Checking duplicates & sending...');

      final firebaseUser = FirebaseAuth.instance.currentUser;
      final token = await firebaseUser?.getIdToken();
      final reporterDetails = await _fetchReporterDetails();

      final finalIncidentType = _selectedIncident == 'Others'
          ? _customIncidentController.text.trim()
          : _selectedIncident;

      final finalHazardType = _selectedHazard == 'Others'
          ? _customHazardController.text.trim()
          : _selectedHazard;

      final String resolvedIncidentType = finalIncidentType.isEmpty ? 'Others' : finalIncidentType;

      // 3. Perform Hybrid Duplicate Check
      final duplicateResult = await _checkIsDuplicate(
        _currentLatitude,
        _currentLongitude,
        resolvedIncidentType,
        maxDistanceMeters: 500,
      );

      final bool isDuplicate = duplicateResult['isDuplicate'] == true;
      final String? parentReportId = duplicateResult['parentReportId'];

      // 🟢 Construct comprehensive report payload
      final Map<String, dynamic> reportPayload = {
        "citizenID": reporterDetails['citizenID'] ?? firebaseUser?.uid ?? 'CID00000000',
        "authUid": firebaseUser?.uid ?? '',
        "submitterName": reporterDetails['name'] ?? 'Anonymous Citizen',
        "submitterEmail": reporterDetails['email'] ?? firebaseUser?.email ?? 'No email provided',
        "submitterPhone": reporterDetails['phone'] ?? firebaseUser?.phoneNumber ?? 'No contact number',
        "mediaUrl": (cloudMediaUrl != null && cloudMediaUrl.isNotEmpty)
            ? cloudMediaUrl
            : (widget.localMediaPath ?? ''),
        "mediaFileName": widget.mediaFileName ?? "captured_media.jpg",
        "incidentType": resolvedIncidentType,
        "severity": _selectedSeverity,
        "hazard": finalHazardType.isEmpty ? 'None' : finalHazardType,
        "notes": _notesController.text.trim(),
        "voiceNoteUrl": cloudAudioUrl,
        "latitude": _currentLatitude,
        "longitude": _currentLongitude,
        "address": _currentAddress,
        "location": {
          "latitude": _currentLatitude,
          "longitude": _currentLongitude,
          "address": _currentAddress,
        },
        "status": isDuplicate ? "duplicate" : "pending",
        "isDuplicate": isDuplicate,
        "parentReportId": parentReportId,
      };

      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      // 4. Send dispatch report to Express backend with Auth Header
      String returnedReportId = _generateRandomId(10);
      bool serverIsDuplicate = isDuplicate;
      String? serverParentId = parentReportId;

      try {
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/reports'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(reportPayload),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = jsonDecode(response.body);
          returnedReportId = responseData['reportID'] ??
              responseData['reportId'] ??
              responseData['id'] ??
              returnedReportId;
          serverIsDuplicate = responseData['isDuplicate'] == true || isDuplicate;
          serverParentId = responseData['parentReportId'] ?? parentReportId;
        }
      } catch (httpErr) {
        debugPrint('⚠️ Backend HTTP submit timeout/error, saving directly: $httpErr');
      }

      // 5. Always persist to Firestore
      await _saveDirectlyToFirestore(returnedReportId, reportPayload, serverIsDuplicate);

      if (mounted) {
        // 🟢 Pass EVERYTHING via spread operator (...) so no field is missing
        final Map<String, dynamic> confirmationPayload = {
          ...reportPayload,
          "id": returnedReportId,
          "reportID": returnedReportId,
          "reportId": returnedReportId,
          "timestamp": DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedDateTime),
          "isDuplicate": serverIsDuplicate,
          "parentReportId": serverParentId,
        };

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ConfirmationSubpage(
              reportId: returnedReportId,
              reportDetails: confirmationPayload,
            ),
          ),
        );
      }

    } catch (error) {
      debugPrint("Error submitting report: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Failed to submit report: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryBlue = isDark ? theme.colorScheme.primary : const Color(0xFF1E40AF);
    final primaryBlueLight = isDark
        ? theme.colorScheme.primaryContainer.withOpacity(0.3)
        : const Color(0xFFEFF6FF);
    final surfaceBg = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final cardBorder = isDark
        ? theme.colorScheme.outline.withOpacity(0.3)
        : const Color(0xFFE2E8F0);
    final textMain = isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
    final textMuted = isDark
        ? theme.colorScheme.onSurfaceVariant
        : const Color(0xFF64748B);

    final mapStyleUrl = isDark
        ? 'https://tiles.openfreemap.org/styles/dark'
        : 'https://tiles.openfreemap.org/styles/liberty';

    final double screenWidth = MediaQuery.of(context).size.width;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double contentPadding = screenWidth > 600 ? 24.0 : 16.0;

    return PopScope(
      canPop: !_isSubmitting, // 🔒 Locks software & hardware back buttons when submitting
      child: Scaffold(
        backgroundColor: surfaceBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          foregroundColor: textMain,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: !_isSubmitting, // 🔒 Hides AppBar back icon when submitting
          title: Text(
            'Submit Incident Report',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textMain),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: cardBorder),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                contentPadding,
                16.0,
                contentPadding,
                bottomPadding > 0 ? bottomPadding + 24.0 : 24.0,
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCard(
                        bgColor: cardBg,
                        borderColor: cardBorder,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: SizedBox(
                                height: 150,
                                width: double.infinity,
                                child: libre.MapLibreMap(
                                  key: ValueKey('${_currentLatitude}_${_currentLongitude}_$isDark'),
                                  styleString: mapStyleUrl,
                                  initialCameraPosition: libre.CameraPosition(
                                    target: libre.LatLng(_currentLatitude, _currentLongitude),
                                    zoom: 15.0,
                                  ),
                                  myLocationEnabled: false,
                                  onMapCreated: (libre.MapLibreMapController controller) {
                                    _reportMapController = controller;
                                  },
                                  onStyleLoadedCallback: () async {
                                    if (_reportMapController != null) {
                                      try {
                                        await _reportMapController!.addCircle(
                                          libre.CircleOptions(
                                            geometry: libre.LatLng(_currentLatitude, _currentLongitude),
                                            circleRadius: 8.0,
                                            circleColor: isDark ? '#60A5FA' : '#1E40AF',
                                            circleStrokeWidth: 2.5,
                                            circleStrokeColor: '#FFFFFF',
                                          ),
                                        );
                                      } catch (e) {
                                        debugPrint("Map marker error: $e");
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(LucideIcons.mapPin, size: 18, color: primaryBlue),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentAddress,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: textMain,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_currentLatitude.toStringAsFixed(5)}, ${_currentLongitude.toStringAsFixed(5)}',
                                              style: TextStyle(fontSize: 11, color: textMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                                    child: Divider(height: 1, color: cardBorder),
                                  ),
                                  Row(
                                    children: [
                                      Icon(LucideIcons.calendar, size: 18, color: primaryBlue),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Date & Time Captured',
                                              style: TextStyle(fontSize: 11, color: textMuted),
                                            ),
                                            Text(
                                              _currentDateTimeFormatted,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: textMain,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (widget.localMediaPath != null && widget.localMediaPath!.isNotEmpty) ...[
                        _buildCard(
                          bgColor: cardBg,
                          borderColor: cardBorder,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.blue.shade900.withOpacity(0.4) : Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LucideIcons.fileImage,
                                  color: isDark ? Colors.blue.shade300 : primaryBlue,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.mediaFileName ?? 'Attached Photo/Video',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textMain),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text('Ready to upload on submission', style: TextStyle(fontSize: 11, color: textMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _onChangeLocationAndRetake, // 🔒 Disabled during submission
                        style: OutlinedButton.styleFrom(
                          backgroundColor: cardBg,
                          foregroundColor: primaryBlue,
                          side: BorderSide(color: cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(LucideIcons.refreshCw, size: 15, color: _isSubmitting ? textMuted : primaryBlue),
                        label: Text(
                          'Change Location or Retake Photo/Video',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _isSubmitting ? textMuted : primaryBlue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      _buildSectionTitle('Incident Type', textMain),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Fire', 'Flood', 'Accident', 'Others'].map((type) {
                          final isSelected = _selectedIncident == type;
                          return ChoiceChip(
                            label: Text(type),
                            selected: isSelected,
                            onSelected: _isSubmitting
                                ? null // 🔒 Disables selection chip during submission
                                : (val) => setState(() => _selectedIncident = type),
                            selectedColor: primaryBlueLight,
                            backgroundColor: cardBg,
                            side: BorderSide(
                              color: isSelected ? primaryBlue : cardBorder,
                              width: 1,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected ? primaryBlue : textMain,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 13,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          );
                        }).toList(),
                      ),
                      _buildAnimatedField(
                        _selectedIncident == 'Others',
                        _customIncidentController,
                        'Specify incident type...',
                        cardBg: cardBg,
                        cardBorder: cardBorder,
                        textMain: textMain,
                        textMuted: textMuted,
                        primaryBlue: primaryBlue,
                        enabled: !_isSubmitting, // 🔒 Disabled input during submission
                      ),
                      const SizedBox(height: 16),

                      // Hazard and severity selection UI intentionally hidden.
                      // Existing state variables remain available for submission,
                      // with defaults of Low severity and None hazard.
                      const SizedBox(height: 4),
                      _buildSectionTitle('Additional Details', textMain),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesController,
                        enabled: !_isSubmitting, // 🔒 Disabled notes textarea during submission
                        maxLines: 3,
                        style: TextStyle(fontSize: 13, color: textMain),
                        decoration: InputDecoration(
                          hintText: 'Add extra details, landmarks, or urgent requests...',
                          hintStyle: TextStyle(color: textMuted, fontSize: 13),
                          filled: true,
                          fillColor: cardBg,
                          contentPadding: const EdgeInsets.all(12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder.withOpacity(0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: primaryBlue, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      _buildCard(
                        bgColor: cardBg,
                        borderColor: cardBorder,
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: (_isSubmitting || (_localAudioPath != null && !_isRecordingAudio))
                                  ? null // 🔒 Disables voice recording during submission
                                  : _toggleAudioRecording,
                              borderRadius: BorderRadius.circular(50),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_localAudioPath != null && !_isRecordingAudio)
                                      ? (isDark ? Colors.grey.shade800 : Colors.grey.shade300)
                                      : (_isRecordingAudio ? Colors.red.shade600 : primaryBlue),
                                ),
                                child: Icon(
                                  _isRecordingAudio ? LucideIcons.square : LucideIcons.mic,
                                  color: (_localAudioPath != null && !_isRecordingAudio)
                                      ? (isDark ? Colors.grey.shade500 : Colors.grey.shade600)
                                      : Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isRecordingAudio
                                        ? 'Recording voice note...'
                                        : (_localAudioPath != null ? 'Voice note ready' : 'Record voice note (1 max)'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _isRecordingAudio ? Colors.red.shade700 : textMain,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isRecordingAudio
                                        ? 'Tap button to stop'
                                        : (_localAudioPath != null
                                        ? 'Will be uploaded on report submission'
                                        : 'Tap mic to add an audio message'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _isRecordingAudio ? Colors.red.shade600 : textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isRecordingAudio)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.red : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '0${(_audioSeconds ~/ 60)}:${(_audioSeconds % 60).toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            else if (_localAudioPath != null)
                              IconButton(
                                onPressed: _isSubmitting ? null : _deleteAudioNote, // 🔒 Disabled trash button during submission
                                icon: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                                tooltip: 'Remove Voice Note',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isSubmitting ? null : _submitFinalReport, // 🔒 Disabled submission button during submission
                          icon: _isSubmitting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(LucideIcons.send, size: 16),
                          label: Text(
                            _isSubmitting ? _submitStatusText : 'Submit Report',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
    required Color bgColor,
    required Color borderColor,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, Color textMain) {
    return Text(
      title,
      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textMain),
    );
  }

  Widget _buildAnimatedField(
      bool isVisible,
      TextEditingController controller,
      String hint, {
        required Color cardBg,
        required Color cardBorder,
        required Color textMain,
        required Color textMuted,
        required Color primaryBlue,
        required bool enabled,
      }) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Visibility(
        visible: isVisible,
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: TextField(
            controller: controller,
            enabled: enabled, // 🔒 Respects submission lock state
            style: TextStyle(fontSize: 13, color: textMain),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: textMuted, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: cardBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cardBorder),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cardBorder.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaryBlue),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
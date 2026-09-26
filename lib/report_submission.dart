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
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'confirmation_subpage.dart';
import 'services/api_service.dart';
import 'services/my_reports_store.dart';
import 'choose_another.dart';
import 'camera_page.dart';
import 'package:alertu_flutter/user_provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as libre;

class ReportSubmissionPage extends ConsumerStatefulWidget {
  final String? localMediaPath;
  final String? mediaFileName;
  final double? latitude;
  final double? longitude;

  const ReportSubmissionPage({
    super.key,
    this.localMediaPath,
    this.mediaFileName,
    this.latitude,
    this.longitude,
  });

  @override
  ConsumerState<ReportSubmissionPage> createState() =>
      _ReportSubmissionPageState();
}

class _ReportSubmissionPageState extends ConsumerState<ReportSubmissionPage> {
  libre.MapLibreMapController? _reportMapController;

  final Nominatim _nominatim = Nominatim.instance;

  late final DateTime _selectedDateTime;
  late final String _currentDateTimeFormatted;

  // Nullable — tile path may open with no location yet
  double? _currentLatitude;
  double? _currentLongitude;
  String _currentAddress = 'Add location';

  bool get _hasLocation =>
      _currentLatitude != null && _currentLongitude != null;

  String? _localMediaPath;
  String? _mediaFileName;

  String _selectedIncident = 'Fire';
  String _selectedSeverity = 'Low';
  String _selectedHazard = 'None';

  final TextEditingController _customIncidentController =
  TextEditingController();
  final TextEditingController _customHazardController =
  TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingAudio = false;
  String? _localAudioPath;
  Timer? _audioTimer;
  int _audioSeconds = 0;

  bool _isSubmitting = false;

  // Fallback only for map picker initial camera when location is still empty
  static const libre.LatLng _bulacanFallback =
  libre.LatLng(14.7925, 120.8970);

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
    _currentDateTimeFormatted =
        DateFormat('MMMM dd, yyyy • hh:mm a').format(_selectedDateTime);

    _currentLatitude = widget.latitude;
    _currentLongitude = widget.longitude;
    _localMediaPath = widget.localMediaPath;
    _mediaFileName = widget.mediaFileName;

    if (_hasLocation) {
      _syncNominatimAddress(_currentLatitude!, _currentLongitude!);
    } else {
      _currentAddress = 'Add location';
    }
  }

  String _generateRandomId([int length = 10]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }


  Future<Map<String, String>> _fetchReporterDetails() async {
    final userProfile = ref.read(userProfileProvider);
    final firebaseUser = FirebaseAuth.instance.currentUser;

    String name = '';
    String email = '';
    String phone = '';
    String citizenID = '';

    if (firebaseUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('citizens')
            .doc(firebaseUser.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          name =
              data['fullName'] ?? data['name'] ?? data['displayName'] ?? '';
          email = data['email'] ?? '';
          phone = data['phoneNumber'] ??
              data['phone'] ??
              data['contactNumber'] ??
              '';
          citizenID =
              data['citizenID'] ?? data['citizenId'] ?? firebaseUser.uid;
        }
      } catch (e) {
        debugPrint('Error fetching user document from Firestore: $e');
      }
    }

    if (name.isEmpty) {
      name = userProfile['name']?.toString() ??
          userProfile['displayName']?.toString() ??
          userProfile['fullName']?.toString() ??
          '';
    }
    if (email.isEmpty) email = userProfile['email']?.toString() ?? '';
    if (phone.isEmpty) {
      phone = userProfile['phoneNumber']?.toString() ??
          userProfile['phone']?.toString() ??
          userProfile['contactNumber']?.toString() ??
          '';
    }

    if (name.isEmpty) name = firebaseUser?.displayName ?? 'Anonymous Citizen';
    if (email.isEmpty) email = firebaseUser?.email ?? 'No email provided';
    if (phone.isEmpty) phone = firebaseUser?.phoneNumber ?? 'Not Provided';
    if (citizenID.isEmpty) citizenID = firebaseUser?.uid ?? 'CID00000000';

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
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      setState(() {
        _currentLatitude = widget.latitude;
        _currentLongitude = widget.longitude;
        if (_hasLocation) {
          _syncNominatimAddress(_currentLatitude!, _currentLongitude!);
        } else {
          _currentAddress = 'Add location';
        }
      });
    }
  }

  Future<void> _syncNominatimAddress(double lat, double lon) async {
    try {
      final Place place = await _nominatim.getAddressFromLatLng(lat, lon);
      if (mounted) {
        setState(() {
          _currentAddress = place.displayName ?? 'Selected Location';
        });
      }
    } catch (e) {
      debugPrint('Address lookup error: $e');
      if (mounted) {
        setState(() {
          _currentAddress =
          'Coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
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
    if (_isSubmitting) return;
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
        final String path = p.join(
          directory.path,
          'audio_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );

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
          _localAudioPath = null;
        });

        _audioTimer?.cancel();
        _audioTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() => _audioSeconds++);
          if (_audioSeconds >= 120) _stopAudioRecording();
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
      debugPrint('Error finalizing audio recording: $e');
      if (mounted) setState(() => _isRecordingAudio = false);
    }
  }

  void _deleteAudioNote() {
    if (_isSubmitting) return;
    setState(() {
      _localAudioPath = null;
      _audioSeconds = 0;
    });
  }

  Future<void> _onEditLocation() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();

    // Bug fix: a report created from the Quick Settings tile has no
    // location yet (_hasLocation is false), so this used to always open
    // the picker centered on the hardcoded _bulacanFallback point instead
    // of where the user actually is. Try a quick GPS fix first; only fall
    // back to Bulacan if permission is denied or the device can't get a
    // fix in time.
    final libre.LatLng initial =
    _hasLocation ? libre.LatLng(_currentLatitude!, _currentLongitude!) : await _resolveDeviceLocationOrFallback();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChooseAnotherPage(
          initialLocation: initial,
          isEditingExistingReport: true,
          onLocationConfirmed: (selectedCoords) {
            setState(() {
              _currentLatitude = selectedCoords.latitude;
              _currentLongitude = selectedCoords.longitude;
              _currentAddress = 'Updating location...';
            });
            _syncNominatimAddress(
              selectedCoords.latitude,
              selectedCoords.longitude,
            );
          },
        ),
      ),
    );
  }

  /// Attempts a one-shot GPS fix (with permission handling) so "Add
  /// Location" opens the map picker centered on the user's real position
  /// instead of the static Bulacan fallback. Any failure -- permission
  /// denied, GPS disabled, no fix within the time limit -- silently falls
  /// back to _bulacanFallback, matching the previous behavior exactly in
  /// the worst case rather than blocking the user from picking a location
  /// manually.
  Future<libre.LatLng> _resolveDeviceLocationOrFallback() async {
    try {
      var status = await Permission.location.status;
      if (status.isDenied) {
        status = await Permission.location.request();
      }
      if (!status.isGranted) return _bulacanFallback;

      if (!await Geolocator.isLocationServiceEnabled()) return _bulacanFallback;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      return libre.LatLng(position.latitude, position.longitude);
    } catch (error) {
      debugPrint('Could not resolve device location for map picker: $error');
      return _bulacanFallback;
    }
  }

  Future<void> _onRetakeMedia() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();

    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPage(
          latitude: _currentLatitude,
          longitude: _currentLongitude,
          isRetake: true,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _localMediaPath = result['path'];
        _mediaFileName = result['fileName'];
      });
    }
  }

  // Bug fix: this used to write to a separate `duplicate_reports`
  // collection with `status: 'duplicate'` when the app's own client-side
  // check thought a report looked similar to an existing one. Duplicate
  // detection is now entirely the backend/admin's responsibility -- every
  // report submitted from the app always lands in the normal `reports`
  // collection as a plain pending report.
  Future<void> _saveDirectlyToFirestore(
      String docId,
      Map<String, dynamic> payload,
      ) async {
    try {
      await FirebaseFirestore.instance.collection('reports').doc(docId).set({
        ...payload,
        'id': docId,
        'reportId': docId,
        'reportID': docId,
        'submittedAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ Direct Firestore save failed: $e');
    }
  }

  Future<void> _submitFinalReport() async {
    if (_isSubmitting) return;

    if (!_hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a location before submitting.'),
        ),
      );
      return;
    }

    if (_isRecordingAudio) {
      await _stopAudioRecording();
    }

    // Bug fix: this used to cycle the button's own label through several
    // status strings ("Uploading media...", "Checking duplicates &
    // sending...", etc). Kept as a plain disabled-button + spinner instead
    // -- see the button widget below, which now just shows "Submitting...".
    setState(() {
      _isSubmitting = true;
    });

    try {
      String? cloudMediaUrl;
      String? cloudAudioUrl;

      if (_localMediaPath != null && _localMediaPath!.isNotEmpty) {
        final file = File(_localMediaPath!);
        if (file.existsSync()) {
          cloudMediaUrl = await ApiService.uploadMediaToB2(_localMediaPath!);
        }
      }

      if (_localAudioPath != null && _localAudioPath!.isNotEmpty) {
        final audioFile = File(_localAudioPath!);
        if (audioFile.existsSync()) {
          cloudAudioUrl = await ApiService.uploadMediaToB2(_localAudioPath!);
        }
      }

      final firebaseUser = FirebaseAuth.instance.currentUser;
      final token = await firebaseUser?.getIdToken();
      final reporterDetails = await _fetchReporterDetails();

      final finalIncidentType = _selectedIncident == 'Others'
          ? _customIncidentController.text.trim()
          : _selectedIncident;

      final finalHazardType = _selectedHazard == 'Others'
          ? _customHazardController.text.trim()
          : _selectedHazard;

      final String resolvedIncidentType =
      finalIncidentType.isEmpty ? 'Others' : finalIncidentType;

      final double lat = _currentLatitude!;
      final double lon = _currentLongitude!;

      // Bug fix: duplicate detection used to run on-device (a Firestore
      // scan of the last 50 reports plus a haversine distance check) and
      // could route a report into a separate `duplicate_reports`
      // collection with `status: 'duplicate'`. That's now entirely the
      // backend/admin's job -- every report the app submits is a plain
      // pending report.
      final Map<String, dynamic> reportPayload = {
        'citizenID':
        reporterDetails['citizenID'] ?? firebaseUser?.uid ?? 'CID00000000',
        'authUid': firebaseUser?.uid ?? '',
        'submitterName': reporterDetails['name'] ?? 'Anonymous Citizen',
        'submitterEmail':
        reporterDetails['email'] ?? firebaseUser?.email ?? 'No email provided',
        'submitterPhone': reporterDetails['phone'] ??
            firebaseUser?.phoneNumber ??
            'No contact number',
        'mediaUrl': (cloudMediaUrl != null && cloudMediaUrl.isNotEmpty)
            ? cloudMediaUrl
            : (_localMediaPath ?? ''),
        'mediaFileName': _mediaFileName ?? 'captured_media.jpg',
        'incidentType': resolvedIncidentType,
        'severity': _selectedSeverity,
        'hazard': finalHazardType.isEmpty ? 'None' : finalHazardType,
        'notes': _notesController.text.trim(),
        'voiceNoteUrl': cloudAudioUrl,
        'latitude': lat,
        'longitude': lon,
        'address': _currentAddress,
        'location': {
          'latitude': lat,
          'longitude': lon,
          'address': _currentAddress,
        },
        'status': 'pending',
      };

      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      String returnedReportId = _generateRandomId(10);

      try {
        final response = await http
            .post(
          Uri.parse('${ApiService.baseUrl}/reports'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(reportPayload),
        )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = jsonDecode(response.body);
          returnedReportId = responseData['reportID'] ??
              responseData['reportId'] ??
              responseData['id'] ??
              returnedReportId;
        }
      } catch (httpErr) {
        debugPrint(
            '⚠️ Backend HTTP submit timeout/error, saving directly: $httpErr');
      }

      await _saveDirectlyToFirestore(
        returnedReportId,
        reportPayload,
      );

      final Map<String, dynamic> confirmationPayload = {
        ...reportPayload,
        'id': returnedReportId,
        'reportID': returnedReportId,
        'reportId': returnedReportId,
        'timestamp':
        DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedDateTime),
        'submittedAt': DateTime.now().toIso8601String(),
      };

      // "My Reports" fix: record the submission in the citizen's own local
      // ledger the moment it succeeds. Previously the tab was a single
      // Firestore query against `reports` filtered by authUid, so a report
      // disappeared from "My Reports" as soon as the backend moved it out
      // of that collection (to `approved_reports` on verification, to
      // `ResolvedReports` on closure). Recording it here means it shows up
      // instantly and then stays in the list through every status change --
      // pending, active and resolved alike -- until the citizen clears that
      // one entry themselves with its "x".
      unawaited(myReportsStore.recordSubmission(confirmationPayload));

      if (mounted) {

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
      debugPrint('Error submitting report: $error');
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

    final primaryBlue =
    isDark ? theme.colorScheme.primary : const Color(0xFF1E40AF);
    final primaryBlueLight = isDark
        ? theme.colorScheme.primaryContainer.withOpacity(0.3)
        : const Color(0xFFEFF6FF);
    final surfaceBg =
    isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final cardBg =
    isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final cardBorder = isDark
        ? theme.colorScheme.outline.withOpacity(0.3)
        : const Color(0xFFE2E8F0);
    final textMain =
    isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
    final textMuted =
    isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);

    final mapStyleUrl = isDark
        ? 'https://tiles.openfreemap.org/styles/dark'
        : 'https://tiles.openfreemap.org/styles/liberty';

    final double screenWidth = MediaQuery.of(context).size.width;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double contentPadding = screenWidth > 600 ? 24.0 : 16.0;

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: surfaceBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          foregroundColor: textMain,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: !_isSubmitting,
          title: Text(
            'Submit Incident Report',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: textMain,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: cardBorder),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Scroll fix: see signup.dart -- onDrag closed the keyboard on
              // the first scroll gesture, so this form (photo, incident type,
              // additional details, etc.) couldn't be scrolled while the
              // keyboard was open. "manual" fixes that; tap-outside still
              // closes the keyboard normally.
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.manual,
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
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              child: SizedBox(
                                height: 150,
                                width: double.infinity,
                                child: _hasLocation
                                    ? libre.MapLibreMap(
                                  key: ValueKey(
                                    '${_currentLatitude}_${_currentLongitude}_$isDark',
                                  ),
                                  styleString: mapStyleUrl,
                                  initialCameraPosition:
                                  libre.CameraPosition(
                                    target: libre.LatLng(
                                      _currentLatitude!,
                                      _currentLongitude!,
                                    ),
                                    zoom: 15.0,
                                  ),
                                  myLocationEnabled: false,
                                  onMapCreated: (controller) {
                                    _reportMapController = controller;
                                  },
                                  onStyleLoadedCallback: () async {
                                    if (_reportMapController == null ||
                                        !_hasLocation) {
                                      return;
                                    }
                                    try {
                                      await _reportMapController!
                                          .addCircle(
                                        libre.CircleOptions(
                                          geometry: libre.LatLng(
                                            _currentLatitude!,
                                            _currentLongitude!,
                                          ),
                                          circleRadius: 8.0,
                                          circleColor: isDark
                                              ? '#60A5FA'
                                              : '#1E40AF',
                                          circleStrokeWidth: 2.5,
                                          circleStrokeColor: '#FFFFFF',
                                        ),
                                      );
                                    } catch (e) {
                                      debugPrint('Map marker error: $e');
                                    }
                                  },
                                )
                                    : Container(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFE2E8F0),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.mapPinOff,
                                          size: 36,
                                          color: textMuted,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No location set',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap Add Location below',
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        LucideIcons.mapPin,
                                        size: 18,
                                        color: primaryBlue,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            if (_hasLocation) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_currentLatitude!.toStringAsFixed(5)}, ${_currentLongitude!.toStringAsFixed(5)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10.0,
                                    ),
                                    child: Divider(height: 1, color: cardBorder),
                                  ),
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.calendar,
                                        size: 18,
                                        color: primaryBlue,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Date & Time Captured',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: textMuted,
                                              ),
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

                      if (_localMediaPath != null &&
                          _localMediaPath!.isNotEmpty) ...[
                        _buildCard(
                          bgColor: cardBg,
                          borderColor: cardBorder,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.blue.shade900.withOpacity(0.4)
                                      : Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LucideIcons.fileImage,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : primaryBlue,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _mediaFileName ?? 'Attached Photo/Video',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: textMain,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ready to upload on submission',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                              _isSubmitting ? null : _onEditLocation,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: cardBg,
                                foregroundColor: primaryBlue,
                                side: BorderSide(color: cardBorder),
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Icon(
                                LucideIcons.mapPin,
                                size: 15,
                                color:
                                _isSubmitting ? textMuted : primaryBlue,
                              ),
                              label: Text(
                                _hasLocation
                                    ? 'Change Location'
                                    : 'Add Location',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color:
                                  _isSubmitting ? textMuted : primaryBlue,
                                ),
                              ),
                            ),
                          ),
                          if (_localMediaPath != null &&
                              _localMediaPath!.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                _isSubmitting ? null : _onRetakeMedia,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: cardBg,
                                  foregroundColor: primaryBlue,
                                  side: BorderSide(color: cardBorder),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: Icon(
                                  LucideIcons.camera,
                                  size: 15,
                                  color:
                                  _isSubmitting ? textMuted : primaryBlue,
                                ),
                                label: Text(
                                  'Retake Photo',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: _isSubmitting
                                        ? textMuted
                                        : primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      _buildSectionTitle('Incident Type', textMain),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                        ['Fire', 'Flood', 'Accident', 'Earthquake', 'Others'].map((type) {
                          final isSelected = _selectedIncident == type;
                          return ChoiceChip(
                            label: Text(type),
                            selected: isSelected,
                            onSelected: _isSubmitting
                                ? null
                                : (_) => setState(
                                  () => _selectedIncident = type,
                            ),
                            selectedColor: primaryBlueLight,
                            backgroundColor: cardBg,
                            side: BorderSide(
                              color: isSelected ? primaryBlue : cardBorder,
                              width: 1,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected ? primaryBlue : textMain,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
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
                        enabled: !_isSubmitting,
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 4),
                      _buildSectionTitle('Additional Details', textMain),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesController,
                        enabled: !_isSubmitting,
                        maxLines: 3,
                        style: TextStyle(fontSize: 13, color: textMain),
                        decoration: InputDecoration(
                          hintText:
                          'Add extra details, landmarks, or urgent requests...',
                          hintStyle:
                          TextStyle(color: textMuted, fontSize: 13),
                          filled: true,
                          fillColor: cardBg,
                          contentPadding: const EdgeInsets.all(12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: cardBorder.withOpacity(0.5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                            BorderSide(color: primaryBlue, width: 1.5),
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
                              onTap: (_isSubmitting ||
                                  (_localAudioPath != null &&
                                      !_isRecordingAudio))
                                  ? null
                                  : _toggleAudioRecording,
                              borderRadius: BorderRadius.circular(50),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_localAudioPath != null &&
                                      !_isRecordingAudio)
                                      ? (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade300)
                                      : (_isRecordingAudio
                                      ? Colors.red.shade600
                                      : primaryBlue),
                                ),
                                child: Icon(
                                  _isRecordingAudio
                                      ? LucideIcons.square
                                      : LucideIcons.mic,
                                  color: (_localAudioPath != null &&
                                      !_isRecordingAudio)
                                      ? (isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade600)
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
                                        : (_localAudioPath != null
                                        ? 'Voice note ready'
                                        : 'Record voice note (1 max)'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _isRecordingAudio
                                          ? Colors.red.shade700
                                          : textMain,
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
                                      color: _isRecordingAudio
                                          ? Colors.red.shade600
                                          : textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isRecordingAudio)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.red
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '0${(_audioSeconds ~/ 60)}:${(_audioSeconds % 60).toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: isDark
                                        ? Colors.red.shade300
                                        : Colors.red.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            else if (_localAudioPath != null)
                              IconButton(
                                onPressed:
                                _isSubmitting ? null : _deleteAudioNote,
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed:
                          _isSubmitting ? null : _submitFinalReport,
                          icon: _isSubmitting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Icon(LucideIcons.send, size: 16),
                          label: Text(
                            _isSubmitting
                                ? 'Submitting...'
                                : 'Submit Report',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
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
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: textMain,
      ),
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
            enabled: enabled,
            style: TextStyle(fontSize: 13, color: textMain),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: textMuted, fontSize: 13),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
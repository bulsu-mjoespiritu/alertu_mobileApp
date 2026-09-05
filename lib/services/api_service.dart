import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  // 🌐 Production Railway Backend URL (appended with /api)
  static String _baseUrl = 'https://alertu-server-production.up.railway.app/api';

  static String get baseUrl => _baseUrl;

  /// Helper to get current Firebase ID Token for backend authentication
  static Future<String?> _getIdToken([bool forceRefresh = false]) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken(forceRefresh);
    } catch (e) {
      print('⚠️ Failed to fetch ID Token: $e');
      return null;
    }
  }

  /// Explicitly sets or verifies backend initialization
  static Future<void> initBackend() async {
    // Directly points to Railway Production Backend
    _baseUrl = 'https://alertu-server-production.up.railway.app/api';
    print('🎉 Connected to Railway Node.js backend at: $_baseUrl');
  }

  // ==========================================
  // Presence & Active Status
  // ==========================================

  /// Sends online/offline state change to Node.js backend REST route
  static Future<bool> updateUserPresence({
    required bool isActive,
    String? uidOverride,
    String? citizenIdOverride,
  }) async {
    try {
      final uid = uidOverride ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return false;

      final token = await _getIdToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/update-presence'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'uid': uid,
          if (citizenIdOverride != null && citizenIdOverride.trim().isNotEmpty)
            'citizenID': citizenIdOverride,
          'isActive': isActive,
          'lastActiveAt': DateTime.now().toIso8601String(),
        }),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('❌ Failed to update presence on backend: $e');
      return false;
    }
  }

  // ==========================================
  // Password Reset / Forgot Password API
  // ==========================================

  static Future<Map<String, dynamic>> sendResetOtp(String email) async {
    try {
      final String targetUrl = '$_baseUrl/auth/send-reset-otp';
      print('📡 Sending OTP request to: $targetUrl');

      final response = await http.post(
        Uri.parse(targetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      );

      print('📥 Response Status Code: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? 'Code sent successfully',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? data['message'] ?? 'Server error (${response.statusCode})',
        };
      }
    } catch (e) {
      print('❌ Exception in sendResetOtp: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Verifies the 6-digit OTP and updates the password in Firebase Auth
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final String targetUrl = '$_baseUrl/auth/reset-password';
      print('📡 Sending Reset Password request to: $targetUrl');

      final response = await http.post(
        Uri.parse(targetUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'otp': otp.trim(),
          'newPassword': newPassword,
        }),
      );

      print('📥 Response Status Code: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? 'Password reset successfully',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? data['message'] ?? 'Failed to reset password',
        };
      }
    } catch (e) {
      print('❌ Exception in resetPassword: $e');
      return {'success': false, 'error': 'Network error. Please try again.'};
    }
  }

  // ==========================================
  // Report Duplicate Checking
  // ==========================================

  /// Checks if an incident report at this location and type is a duplicate
  static Future<Map<String, dynamic>?> checkDuplicateReport({
    required double latitude,
    required double longitude,
    required String incidentType,
  }) async {
    try {
      final token = await _getIdToken();
      final String targetUrl = '$_baseUrl/reports/check-duplicate';

      print('📡 Checking duplicate report at: $targetUrl');

      final response = await http.post(
        Uri.parse(targetUrl),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'incidentType': incidentType,
        }),
      );

      print('📥 Duplicate Check Response Status: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data;
      } else {
        print('⚠️ Duplicate check endpoint returned non-200 code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Exception in checkDuplicateReport: $e');
      return null;
    }
  }

  // ==========================================
  // Media & Messaging Methods
  // ==========================================

  static Future<String?> uploadMediaToB2(String localFilePath) async {
    try {
      final file = File(localFilePath);
      if (!file.existsSync()) {
        print("❌ ERROR: Local file does not exist at path: $localFilePath");
        return null;
      }

      final token = await _getIdToken();
      final String baseFileName = localFilePath.split('/').last;
      final String lowerPath = localFilePath.toLowerCase();

      // Normalize MIME types across platforms
      String contentType = 'image/jpeg';
      if (lowerPath.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lowerPath.endsWith('.mp4')) {
        contentType = 'video/mp4';
      } else if (lowerPath.endsWith('.aac') || lowerPath.endsWith('.m4a')) {
        contentType = 'audio/aac';
      }

      print('1️⃣ Requesting upload link from Node for: $baseFileName ($contentType)');

      final urlResponse = await http.post(
        Uri.parse('$_baseUrl/media/get-upload-url'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'fileType': contentType,
          'fileName': baseFileName,
        }),
      );

      if (urlResponse.statusCode != 200) {
        print('❌ ERROR: Backend server failed (Status ${urlResponse.statusCode}): ${urlResponse.body}');
        return null;
      }

      final data = jsonDecode(urlResponse.body);
      if (data['success'] != true) {
        print('❌ ERROR: Backend responded success=false');
        return null;
      }

      final String uploadUrl = data['uploadUrl'];
      final String rawFileUrl = data['fileUrl'];
      final String requiredContentType = data['requiredContentType'] ?? contentType;

      String fullFileUrl = rawFileUrl;
      if (rawFileUrl.startsWith('/api') || rawFileUrl.startsWith('/')) {
        final String origin = _baseUrl.substring(0, _baseUrl.lastIndexOf('/api'));
        fullFileUrl = '$origin$rawFileUrl';
      }

      print('2️⃣ Node generated presigned URL successfully.');

      final fileBytes = await file.readAsBytes();

      print('3️⃣ Transmitting ${fileBytes.length} bytes directly to Backblaze...');

      // Direct PUT upload to Backblaze B2
      final b2Response = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': requiredContentType,
        },
        body: fileBytes,
      );

      if (b2Response.statusCode == 200 || b2Response.statusCode == 201) {
        print('✅ SUCCESS: Asset accepted by Backblaze! Absolute URL: $fullFileUrl');
        return fullFileUrl;
      } else {
        print('❌ BACKBLAZE REJECTED UPLOAD!');
        print('Status Code: ${b2Response.statusCode}');
        print('B2 Raw Error Body: ${b2Response.body}');
        return null;
      }
    } catch (e) {
      print('❌ CRITICAL NETWORK EXCEPTION: $e');
      return null;
    }
  }

  static Future<bool> registerFcmToken(String fcmToken) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final token = await _getIdToken();

      final response = await http.post(
        Uri.parse('$_baseUrl/register-fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'fcmToken': fcmToken,
          'uid': uid,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Failed to register FCM token: $e');
      return false;
    }
  }
}
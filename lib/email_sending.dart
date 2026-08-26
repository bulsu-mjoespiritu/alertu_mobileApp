import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alertu_flutter/homepage.dart';
import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EmailSendingScreen extends ConsumerStatefulWidget {
  const EmailSendingScreen({super.key});

  @override
  ConsumerState<EmailSendingScreen> createState() => _EmailSendingScreenState();
}

class _EmailSendingScreenState extends ConsumerState<EmailSendingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _otpController = TextEditingController();
  final Color primaryColor = const Color(0xff0d47a1);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Flow & Action states
  bool _isDispatching = false;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _codeSent = false;
  bool _canResend = false;

  // Timer properties
  Timer? _countdownTimer;
  int _secondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _initAnimations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUserSession();
      _handleOtpDispatch();
    });
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _checkUserSession() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      _showSnackBar(
        "Session Expired",
        "Please sign in or register to verify your email.",
        isError: true,
      );
      _redirectToWrapper();
    }
  }

  void _redirectToWrapper() {
    if (!mounted) return;
    _countdownTimer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Wrapper()),
          (route) => false,
    );
  }

  // 🕒 Fixed active Timer tracking
  void _startTimer() {
    _countdownTimer?.cancel(); // Cancel any existing active instance

    if (!mounted) return;

    setState(() {
      _canResend = false;
      _secondsRemaining = 60;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _canResend = true;
          _secondsRemaining = 0;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  /// Safely resolves full endpoint URL avoiding double `/api/api` paths
  Future<String> _getResolvedEndpoint(String path) async {
    if (ApiService.baseUrl == null || ApiService.baseUrl!.isEmpty) {
      await ApiService.initBackend();
    }

    String base = ApiService.baseUrl ?? 'https://alertu-server.onrender.com';

    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    if (base.endsWith('/api') && path.startsWith('/api/')) {
      path = path.substring(4);
    } else if (!base.endsWith('/api') && !path.startsWith('/api/') && !path.startsWith('/')) {
      path = '/$path';
    }

    return '$base$path';
  }

  /// Secure POST request executor
  Future<Map<String, dynamic>?> _executeSecurePost({
    required String endpoint,
    required Map<String, dynamic> payload,
    required String idToken,
    required Duration timeout,
  }) async {
    final uri = Uri.parse(endpoint);

    if (uri.scheme != 'https') {
      debugPrint('🚨 [Security Block] Insecure HTTP request blocked.');
      if (mounted) {
        _showSnackBar("Security Alert", "Insecure connections are not allowed.", isError: true);
      }
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri);
      request.followRedirects = false;

      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $idToken');
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close();

      if (response.isRedirect || (response.statusCode >= 300 && response.statusCode < 400)) {
        final redirectUrl = response.headers.value(HttpHeaders.locationHeader);
        debugPrint('🚨 [Security Block] Redirect attempt intercepted -> $redirectUrl');
        if (mounted) {
          _showSnackBar(
            "Security Warning",
            "An unauthorized redirect attempt was blocked.",
            isError: true,
          );
        }
        return null;
      }

      final responseBody = await response.transform(utf8.decoder).join();

      if (responseBody.trim().startsWith('<') ||
          response.headers.value(HttpHeaders.contentTypeHeader)?.contains('text/html') == true) {
        debugPrint('❌ Unexpected HTML Response (${response.statusCode}): $responseBody');
        if (mounted) {
          _showSnackBar("Server Error", "Invalid response returned from server.", isError: true);
        }
        return null;
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      data['_statusCode'] = response.statusCode;
      return data;
    } finally {
      client.close();
    }
  }

  Future<void> _handleOtpDispatch({bool isResend = false}) async {
    if (_isDispatching || _isResending) return;

    if (mounted) {
      setState(() {
        if (isResend) {
          _isResending = true;
        } else {
          _isDispatching = true;
        }
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        if (mounted) _redirectToWrapper();
        return;
      }

      await user.reload();
      final String? idToken = await user.getIdToken(true);

      if (idToken == null) {
        if (mounted) {
          _showSnackBar("Auth Error", "Could not verify identity token.", isError: true);
        }
        return;
      }

      final String otpEndpoint = await _getResolvedEndpoint('/api/email-verification/send-otp');
      debugPrint('📡 [OTP Dispatch] POST -> $otpEndpoint');

      final result = await _executeSecurePost(
        endpoint: otpEndpoint,
        payload: {
          'uid': user.uid,
          'email': user.email,
        },
        idToken: idToken,
        timeout: const Duration(seconds: 25),
      );

      if (result == null) return;

      final int statusCode = result['_statusCode'] ?? 500;

      if (statusCode == 200 && (result['success'] == true || result['status'] == 'success')) {
        if (mounted) {
          setState(() => _codeSent = true);
          _showSnackBar(
            isResend ? "Code Resent" : "Code Dispatched",
            "Verification code sent directly to your email inbox.",
          );
        }
        _startTimer();
      } else {
        final msg = result['message'] ?? result['error'] ?? 'Failed to send verification code.';
        if (mounted) {
          _showSnackBar("Notice", msg, isError: statusCode != 429);
          if (statusCode == 429) {
            setState(() => _codeSent = true);
            _startTimer(); // Always start timer if rate limited
          }
        }
      }
    } catch (e) {
      debugPrint("❌ OTP Dispatch Error: $e");
      if (mounted) {
        _showSnackBar(
          "Connection Error",
          "Could not reach backend service. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDispatching = false;
          _isResending = false;
        });
      }
    }
  }

  Future<void> _verifyOtpCode() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _showSnackBar(
        "Invalid Code",
        "Please enter the complete 6-digit verification code.",
        isError: true,
      );
      return;
    }

    if (mounted) setState(() => _isVerifying = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        _showSnackBar("Session Lost", "No active session found.", isError: true);
        _redirectToWrapper();
        return;
      }

      await user.reload();
      final String? idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        _showSnackBar("Auth Error", "Failed to retrieve user authorization token.", isError: true);
        return;
      }

      final String verifyEndpoint = await _getResolvedEndpoint('/api/email-verification/verify-otp');
      debugPrint('📡 [OTP Verify] POST -> $verifyEndpoint');

      final result = await _executeSecurePost(
        endpoint: verifyEndpoint,
        payload: {
          'uid': user.uid,
          'email': user.email,
          'otp': code,
        },
        idToken: idToken,
        timeout: const Duration(seconds: 20),
      );

      if (result == null) return;

      final int statusCode = result['_statusCode'] ?? 500;

      if (statusCode == 200 && (result['success'] == true || result['status'] == 'success')) {
        final verifiedUser = FirebaseAuth.instance.currentUser;
        if (verifiedUser != null) {
          await FirebaseFirestore.instance.collection('citizens').doc(verifiedUser.uid).set(
            {'emailVerified': true},
            SetOptions(merge: true),
          );
          await verifiedUser.reload();
        }
        if (mounted) {
          _showSnackBar("Verified", "Email verified successfully!");
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const Homepage()),
                (route) => false,
          );
        }
      } else {
        final msg = result['message'] ?? result['error'] ?? 'Incorrect or expired verification code.';
        if (mounted) _showSnackBar("Verification Failed", msg, isError: true);
      }
    } catch (e) {
      debugPrint("❌ OTP Verification Error: $e");
      if (mounted) {
        _showSnackBar(
          "Connection Error",
          "Could not reach verification server.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showSnackBar(String title, String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade900 : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final mediaQuery = MediaQuery.of(context);
    final isWideScreen = mediaQuery.size.width > 600;

    return Theme(
      data: ThemeData.light().copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xfff8fafc),
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          surface: Colors.white,
          onSurface: const Color(0xff0f172a),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xfff8fafc),
        appBar: AppBar(
          title: const Text(
            'Email Verification',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: Colors.white,
          foregroundColor: primaryColor,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.logOut, size: 20),
              onPressed: () async {
                _countdownTimer?.cancel();
                await FirebaseAuth.instance.signOut();
                _redirectToWrapper();
              },
            )
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isWideScreen ? 48.0 : 24.0,
                vertical: 24.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withOpacity(0.08),
                          ),
                          child: Icon(
                            _codeSent ? LucideIcons.mailCheck : LucideIcons.send,
                            size: 42,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _codeSent ? 'Enter Security Code' : 'Dispatching Security Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: isWideScreen ? 24 : 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xff0f172a),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _codeSent
                            ? 'We sent a 6-digit verification code to:\n${user?.email ?? "your registered email"}'
                            : 'Generating a secure 6-digit verification code and sending it directly to your registered inbox...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (_isDispatching) ...[
                        Container(
                          width: double.infinity,
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.grey.shade200,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                      ],
                      if (_codeSent) ...[
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff0f172a),
                            letterSpacing: 8,
                          ),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (val) {
                            if (val.trim().length == 6) {
                              _verifyOtpCode();
                            }
                          },
                          decoration: InputDecoration(
                            counterText: "",
                            hintText: "••••••",
                            hintStyle: TextStyle(
                              color: Colors.grey.shade300,
                              letterSpacing: 8,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: primaryColor, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FButton(
                            onPress: _isVerifying ? null : _verifyOtpCode,
                            child: _isVerifying
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text(
                              'Confirm Code',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: (_canResend && !_isResending)
                              ? () => _handleOtpDispatch(isResend: true)
                              : null,
                          child: _isResending
                              ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                              : Text(
                            _canResend
                                ? 'Resend Verification Code'
                                : 'Resend code in ${_secondsRemaining}s',
                            style: TextStyle(
                              color: _canResend ? primaryColor : Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
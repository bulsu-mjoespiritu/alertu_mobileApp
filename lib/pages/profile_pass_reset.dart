import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/api_service.dart';

final profilePassResetLoadingProvider = StateProvider<bool>((ref) => false);
final profilePassResetStepProvider = StateProvider<int>((ref) => 1);

class ProfilePassResetPage extends ConsumerStatefulWidget {
  const ProfilePassResetPage({super.key});

  @override
  ConsumerState<ProfilePassResetPage> createState() => _ProfilePassResetPageState();
}

class _ProfilePassResetPageState extends ConsumerState<ProfilePassResetPage> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;

  // Real-time password strength trackers
  String _strengthText = "Weak";
  Color _strengthColor = Colors.red;
  double _strengthProgress = 0.33;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_evaluatePasswordStrength);

    // Auto-populate logged-in user's email & reset state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email != null) {
        _emailController.text = user!.email!;
      }
      ref.read(profilePassResetStepProvider.notifier).state = 1;
      ref.read(profilePassResetLoadingProvider.notifier).state = false;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Real-time password strength evaluation algorithm
  void _evaluatePasswordStrength() {
    final text = _passwordController.text;
    final uppercaseCount = text.replaceAll(RegExp(r'[^A-Z]'), '').length;
    final specialCharCount = text.replaceAll(RegExp(r'[a-zA-Z0-9\s]'), '').length;
    // Bug fix: rules changed from "exactly 15+ chars, exactly 1 uppercase,
    // exactly 1 special char" to "8-15 chars, at least 1 of each".
    final bool hasValidLength = text.length >= 8 && text.length <= 15;

    if (text.length < 8) {
      setState(() {
        _strengthText = "Weak";
        _strengthColor = Colors.red;
        _strengthProgress = 0.33;
      });
    } else if (hasValidLength && uppercaseCount >= 1 && specialCharCount >= 1) {
      setState(() {
        _strengthText = "Strong";
        _strengthColor = Colors.green;
        _strengthProgress = 1.0;
      });
    } else {
      setState(() {
        _strengthText = "Moderate";
        _strengthColor = Colors.amber;
        _strengthProgress = 0.66;
      });
    }
  }

  // Step 1: Send OTP to Email
  Future<void> _handleSendOtp() async {
    if (ref.read(profilePassResetLoadingProvider)) return;

    if (ref.read(profilePassResetStepProvider) == 1) {
      if (_emailFormKey.currentState == null || !_emailFormKey.currentState!.validate()) {
        return;
      }
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Error', 'Please enter a valid email address.', isError: true);
      return;
    }

    ref.read(profilePassResetLoadingProvider.notifier).state = true;

    final response = await ApiService.sendResetOtp(email);

    if (!mounted) return;

    ref.read(profilePassResetLoadingProvider.notifier).state = false;

    final bool isSuccess = response['success'] == true || response['success'] == 'true';

    if (isSuccess) {
      _showSnackBar(
        'Code Sent',
        'We sent a 6-digit verification code to $email.',
        isError: false,
      );
      ref.read(profilePassResetStepProvider.notifier).state = 2;
    } else {
      _showSnackBar(
        'Request Failed',
        response['error']?.toString() ?? 'Could not send verification code.',
        isError: true,
      );
    }
  }

  // Step 2: Verify OTP & Update Password
  Future<void> _handleResetPassword() async {
    if (ref.read(profilePassResetLoadingProvider)) return;
    if (!_resetFormKey.currentState!.validate()) return;

    ref.read(profilePassResetLoadingProvider.notifier).state = true;

    final response = await ApiService.resetPassword(
      email: _emailController.text.trim(),
      otp: _otpController.text.trim(),
      newPassword: _passwordController.text,
    );

    if (!mounted) return;

    ref.read(profilePassResetLoadingProvider.notifier).state = false;

    final bool isSuccess = response['success'] == true || response['success'] == 'true';

    if (isSuccess) {
      _showSnackBar(
        'Success',
        'Your password has been changed successfully.',
        isError: false,
      );
      Navigator.pop(context);
    } else {
      _showSnackBar(
        'Update Failed',
        response['error']?.toString() ?? 'Failed to reset password. Please try again.',
        isError: true,
      );
    }
  }

  void _showSnackBar(String title, String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultPrimary = isDark ? Theme.of(context).colorScheme.primary : const Color(0xFF0D47A1);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade800 : defaultPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.roboto(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final labelColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);
    final hintColor = isDark ? theme.colorScheme.onSurfaceVariant.withOpacity(0.6) : Colors.grey.shade400;

    final fillColor = enabled
        ? (isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white)
        : (isDark ? theme.colorScheme.surfaceContainerLow : Colors.grey.shade100);

    final borderColor = isDark ? theme.colorScheme.outline.withOpacity(0.3) : Colors.grey.shade300;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      labelStyle: GoogleFonts.roboto(color: labelColor, fontSize: 14),
      hintStyle: GoogleFonts.roboto(color: hintColor, fontSize: 14),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final cardColor = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final titleColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF1E293B);

    final isLoading = ref.watch(profilePassResetLoadingProvider);
    final currentStep = ref.watch(profilePassResetStepProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0.5,
        foregroundColor: primaryColor,
        title: Text(
          'Change Password',
          style: GoogleFonts.roboto(
            color: titleColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: titleColor),
          onPressed: () {
            if (currentStep == 2) {
              ref.read(profilePassResetStepProvider.notifier).state = 1;
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      )
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: isDark ? Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)) : null,
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: currentStep == 1
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: _buildStepOneForm(),
                  secondChild: _buildStepTwoForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Step 1: Send Verification Code ---
  Widget _buildStepOneForm() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final headingColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF1E293B);
    final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);

    final isLoading = ref.watch(profilePassResetLoadingProvider);

    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.keyRound,
              size: 32,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Security Verification',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'To update your account password, we need to send a 6-digit verification code to your email address.',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: subtitleColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            readOnly: true, // Email is locked to the logged-in user
            style: TextStyle(color: headingColor),
            decoration: _buildInputDecoration(
              labelText: 'Email Address',
              hintText: 'name@example.com',
              enabled: false,
              prefixIcon: Icon(LucideIcons.mail, size: 20, color: primaryColor),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.send, size: 18, color: Colors.white),
              label: Text(
                'Send Verification Code',
                style: GoogleFonts.roboto(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              onPressed: isLoading ? null : _handleSendOtp,
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 2: Enter OTP & Set New Password ---
  Widget _buildStepTwoForm() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final headingColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF1E293B);
    final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);

    final isLoading = ref.watch(profilePassResetLoadingProvider);

    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.mailCheck,
              size: 32,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Enter Verification Code',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: headingColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A 6-digit code was sent to ${_emailController.text}. Enter code below along with your new password.',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: subtitleColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: TextStyle(color: headingColor),
            decoration: _buildInputDecoration(
              labelText: '6-Digit Code',
              hintText: '123456',
              prefixIcon: Icon(LucideIcons.shieldCheck, size: 20, color: primaryColor),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter the code';
              if (v.trim().length != 6) return 'Code must be 6 digits';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            style: TextStyle(color: headingColor),
            decoration: _buildInputDecoration(
              labelText: 'New Password',
              hintText: 'Enter new password',
              prefixIcon: Icon(LucideIcons.lock, size: 20, color: primaryColor),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 20,
                  color: subtitleColor,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password cannot be empty';
              if (v.length < 15) return 'Password must be at least 15 characters total';

              final uppercaseCount = v.replaceAll(RegExp(r'[^A-Z]'), '').length;
              if (uppercaseCount != 1) return 'Must contain exactly 1 uppercase letter';

              final specialCharCount = v.replaceAll(RegExp(r'[a-zA-Z0-9\s]'), '').length;
              if (specialCharCount != 1) return 'Must contain exactly 1 special character';

              return null;
            },
          ),
          const SizedBox(height: 10),

          // Password Strength Meter
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Password Strength:',
                    style: GoogleFonts.roboto(fontSize: 12, color: subtitleColor),
                  ),
                  Text(
                    _strengthText,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _strengthColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _strengthProgress,
                  backgroundColor: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                  minHeight: 5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.check, size: 18, color: Colors.white),
              label: Text(
                'Update Password',
                style: GoogleFonts.roboto(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              onPressed: isLoading ? null : _handleResetPassword,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: isLoading ? null : _handleSendOtp,
            child: Text(
              'Resend Verification Code',
              style: GoogleFonts.roboto(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
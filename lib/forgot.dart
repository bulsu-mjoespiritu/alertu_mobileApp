import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

// 🔄 Standard Notifier implementations (Replacing legacy StateProvider)
class ForgotLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final forgotLoadingProvider = NotifierProvider<ForgotLoadingNotifier, bool>(
  ForgotLoadingNotifier.new,
);

class ForgotStepNotifier extends Notifier<int> {
  @override
  int build() => 1; // Step 1: Request OTP | Step 2: Verify & Reset

  void set(int step) => state = step;
}

final forgotStepProvider = NotifierProvider<ForgotStepNotifier, int>(
  ForgotStepNotifier.new,
);

class Forgot extends ConsumerStatefulWidget {
  const Forgot({super.key});

  @override
  ConsumerState<Forgot> createState() => _ForgotState();
}

class _ForgotState extends ConsumerState<Forgot> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false;

  // Real-time password strength trackers (Matching SignUp)
  String _strengthText = "Weak";
  Color _strengthColor = Colors.red;
  double _strengthProgress = 0.33;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_evaluatePasswordStrength);

    // Ensure screen always starts cleanly at Step 1
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(forgotStepProvider.notifier).set(1);
      ref.read(forgotLoadingProvider.notifier).set(false);
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
    final hasValidLength = text.length >= 12 && text.length <= 20;
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(text);
    final hasSpecialCharacter = RegExp(r'[!@#\$%\^&\*]').hasMatch(text);

    if (text.isEmpty || !hasValidLength || !hasUppercase || !hasSpecialCharacter) {
      setState(() {
        _strengthText = "Weak";
        _strengthColor = Colors.red;
        _strengthProgress = 0.33;
      });
    } else {
      setState(() {
        _strengthText = "Strong";
        _strengthColor = Colors.green;
        _strengthProgress = 1.0;
      });
    }
  }

  // Step 1: Send OTP to Email (Safely handles both Step 1 & Step 2 Resend)
  Future<void> _handleSendOtp() async {
    if (ref.read(forgotLoadingProvider)) return;

    // Only validate form state if we are currently on Step 1
    if (ref.read(forgotStepProvider) == 1) {
      if (_emailFormKey.currentState == null || !_emailFormKey.currentState!.validate()) {
        return;
      }
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Error', 'Please enter a valid email address.', isError: true);
      return;
    }

    ref.read(forgotLoadingProvider.notifier).set(true);

    final response = await ApiService.sendResetOtp(email);

    if (!mounted) return;

    ref.read(forgotLoadingProvider.notifier).set(false);

    final bool isSuccess = response['success'] == true || response['success'] == 'true';

    if (isSuccess) {
      _showSnackBar(
        'Code Sent',
        response['message']?.toString() ?? 'We sent a 6-digit code to your email address.',
        isError: false,
      );
      ref.read(forgotStepProvider.notifier).set(2);
    } else {
      _showSnackBar(
        'Request Failed',
        response['message']?.toString() ?? response['error']?.toString() ?? 'Could not send verification code.',
        isError: true,
      );
    }
  }

  // Step 2: Verify OTP & Reset Password
  Future<void> _handleResetPassword() async {
    if (ref.read(forgotLoadingProvider)) return;
    if (!_resetFormKey.currentState!.validate()) return;

    ref.read(forgotLoadingProvider.notifier).set(true);

    final response = await ApiService.resetPassword(
      email: _emailController.text.trim(),
      otp: _otpController.text.trim(),
      newPassword: _passwordController.text,
    );

    if (!mounted) return;

    ref.read(forgotLoadingProvider.notifier).set(false);

    final bool isSuccess = response['success'] == true || response['success'] == 'true';

    if (isSuccess) {
      _showSnackBar(
        'Success',
        response['message']?.toString() ?? 'Your password has been reset successfully.',
        isError: false,
      );
      Navigator.pop(context);
    } else {
      _showSnackBar(
        'Reset Failed',
        response['message']?.toString() ?? response['error']?.toString() ?? 'Failed to reset password. Please try again.',
        isError: true,
      );
    }
  }

  void _showSnackBar(String title, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF0D47A1),
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
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      labelStyle: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 14),
      hintStyle: GoogleFonts.roboto(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(forgotLoadingProvider);
    final currentStep = ref.watch(forgotStepProvider);

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth >= 600;

    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0D47A1),
          surface: Colors.white,
          onSurface: Color(0xFF1E293B),
        ),
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          title: Text(
            'Reset Password',
            style: GoogleFonts.roboto(
              color: const Color(0xFF1E293B),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0D47A1)),
            onPressed: () {
              if (currentStep == 2) {
                ref.read(forgotStepProvider.notifier).set(1);
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        body: isLoading
            ? const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
          ),
        )
            : SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                isTablet ? 32.0 : 20.0,
                24.0,
                isTablet ? 32.0 : 20.0,
                24.0 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 480 : 400,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: currentStep == 1
                          ? _buildStepOneForm()
                          : _buildStepTwoForm(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Step 1: Request Code ---
  Widget _buildStepOneForm() {
    final isLoading = ref.watch(forgotLoadingProvider);

    return Form(
      key: _emailFormKey,
      child: Column(
        key: const ValueKey(1),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_reset_rounded,
            size: 48,
            color: Color(0xFF0D47A1),
          ),
          const SizedBox(height: 16),
          Text(
            'Forgot Password?',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your registered email below, and we'll send you a 6-digit code to reset your password.",
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _emailController,
            style: GoogleFonts.roboto(color: const Color(0xFF1E293B)),
            keyboardType: TextInputType.emailAddress,
            decoration: _buildInputDecoration(
              labelText: 'Email Address',
              hintText: 'name@example.com',
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF0D47A1)),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isLoading ? null : _handleSendOtp,
            child: Text(
              'Send Verification Code',
              style: GoogleFonts.roboto(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 2: Code & New Password ---
  Widget _buildStepTwoForm() {
    final isLoading = ref.watch(forgotLoadingProvider);

    return Form(
      key: _resetFormKey,
      child: Column(
        key: const ValueKey(2),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 48,
            color: Color(0xFF0D47A1),
          ),
          const SizedBox(height: 16),
          Text(
            'Check Your Email',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to ${_emailController.text}. Enter code and set new password.',
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _otpController,
            style: GoogleFonts.roboto(color: const Color(0xFF1E293B)),
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: _buildInputDecoration(
              labelText: '6-Digit Code',
              hintText: '123456',
              prefixIcon: const Icon(Icons.pin_outlined, color: Color(0xFF0D47A1)),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter the code';
              if (v.trim().length != 6) return 'Code must be 6 digits';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            style: GoogleFonts.roboto(color: const Color(0xFF1E293B)),
            obscureText: !_isPasswordVisible,
            decoration: _buildInputDecoration(
              labelText: 'New Password',
              hintText: 'Enter new password',
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF0D47A1)),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
            ),
            validator: (v) {
              final value = v ?? '';
              if (value.isEmpty) return 'Password cannot be empty';
              if (value.length < 12 || value.length > 20) {
                return 'Password must be between 12 and 20 characters';
              }
              if (!RegExp(r'[A-Z]').hasMatch(value)) {
                return 'Password must contain at least 1 uppercase letter (A-Z)';
              }
              if (!RegExp(r'[!@#\$%\^&\*]').hasMatch(value)) {
                return 'Password must contain at least 1 special character (!@#\$%^&*)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Password Strength:',
                    style: GoogleFonts.roboto(fontSize: 12, color: const Color(0xFF64748B)),
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
              LinearProgressIndicator(
                value: _strengthProgress,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                minHeight: 5,
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isLoading ? null : _handleResetPassword,
            child: Text(
              'Reset Password',
              style: GoogleFonts.roboto(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: isLoading ? null : _handleSendOtp,
            child: Text(
              'Resend Code',
              style: GoogleFonts.roboto(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF0D47A1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
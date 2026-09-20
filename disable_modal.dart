import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:alertu_flutter/services/socket.dart';
import 'package:alertu_flutter/login.dart';

class DisableModal extends StatelessWidget {
  final bool isDialog;

  const DisableModal({super.key, this.isDialog = true});

  /// Opens the non-dismissible dialog overlay (used on active screens like Homepage)
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevents closing by tapping background
      builder: (BuildContext dialogContext) {
        return const PopScope(
          canPop: false, // Prevents closing using the back button
          child: DisableModal(isDialog: true),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget cardContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.block_rounded,
            size: 48,
            color: isDark ? Colors.red.shade400 : Colors.red.shade700,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Account Deactivated",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Your account was turned off by an admin. Please log in again or contact support for assistance.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              // 1. Reset the global deactivation flag
              SocketService.isAccountDeactivatedFlag = false;

              // 2. If shown as a dialog on top of active screen, pop it safely
              if (isDialog && Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop();
              }

              // 3. Clean up active socket session
              try {
                SocketService.disconnect();
              } catch (_) {}

              // 4. Sign out Firebase session
              await FirebaseAuth.instance.signOut();

              // 5. If loaded full-screen inside Wrapper, manually route to Login
              if (!isDialog && context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const Login()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xff1565c0) : const Color(0xff0d47a1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 0,
            ),
            child: const Text(
              "Back to Login",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );

    // 1. Used as Overlay Dialog (e.g., DisableModal.show(context))
    if (isDialog) {
      return AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: cardContent,
      );
    }

    // 2. Used directly in Scaffold body inside Wrapper
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade200,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Dialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              elevation: 6,
              insetPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: cardContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
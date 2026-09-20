import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'SlideToSOSButton.dart'; // Adjust path if needed

class SOS_Button extends StatelessWidget {
  final String citizenId;
  final String submitterName;
  final String email;
  final String phone;
  final List<Map<String, String>> emergencyContacts;

  const SOS_Button({
    super.key,
    this.citizenId = '',
    this.submitterName = '',
    this.email = '',
    this.phone = '',
    this.emergencyContacts = const [],
  });

  void _openSOSModal(BuildContext context) {
    HapticFeedback.mediumImpact();

    // Directly present the updated Modal containing the non-dismissible loading state & no X icon
    showEmergencySosModal(
      context: context,
      citizenId: citizenId,
      submitterName: submitterName,
      email: email,
      phone: phone,
      emergencyContacts: emergencyContacts,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double buttonSize = 54.0;

    return GestureDetector(
      onTap: () => _openSOSModal(context),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444), // Crimson Red
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x66EF4444),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
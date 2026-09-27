import 'package:flutter/material.dart';

class UserPinpointButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading; // 🎯 Added: Track if hardware is fetching location

  /// True when device location services are off (or permission is
  /// permanently denied). The button stays tappable so the user can react
  /// to it (onPressed should open location settings in that case) — it
  /// just renders in a muted "inactive" state instead of the normal one,
  /// the same way Google Maps grays its locator button out when GPS is off.
  final bool isDisabled;

  const UserPinpointButton({
    super.key,
    required this.onPressed,
    this.isLoading = false, // Defaults to false
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        isDisabled ? const Color(0xFF9CA3AF) : const Color(0xFF0D47A1);

    return GestureDetector(
      onTap: isLoading ? null : onPressed, // Prevent double-tapping while active
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading
            ? SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        )
            : Icon(
          isDisabled ? Icons.location_disabled : Icons.my_location,
          color: iconColor,
          size: 24,
        ),
      ),
    );
  }
}

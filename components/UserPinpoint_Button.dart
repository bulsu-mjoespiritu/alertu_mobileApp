import 'package:flutter/material.dart';

class UserPinpointButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading; // 🎯 Added: Track if hardware is fetching location

  const UserPinpointButton({
    super.key,
    required this.onPressed,
    this.isLoading = false, // Defaults to false
  });

  @override
  Widget build(BuildContext context) {
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
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
          ),
        )
            : const Icon(
          Icons.my_location,
          color: Color(0xFF0D47A1),
          size: 24,
        ),
      ),
    );
  }
}

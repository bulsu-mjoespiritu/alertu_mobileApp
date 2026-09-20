import 'package:flutter/material.dart';

class FeedbackService {
  static void show(BuildContext context, String message, {String type = 'error'}) {
    Color bgColor;
    IconData icon;

    switch (type) {
      case 'success':
        bgColor = Colors.green.shade700;
        icon = Icons.check_circle_outline;
        break;
      case 'warning':
        bgColor = Colors.orange.shade800;
        icon = Icons.warning_amber_rounded;
        break;
      case 'error':
      default:
        bgColor = Colors.red.shade700;
        icon = Icons.error_outline;
        break;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PHClockCard extends StatelessWidget {
  final Stream<DateTime> timeStream;

  const PHClockCard({super.key, required this.timeStream});

  @override
  Widget build(BuildContext context) {
    // Check if current theme is dark mode
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-adaptive color palette
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : Colors.grey.shade100;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF212121);
    final secondaryTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;
    final shadowOpacity = isDark ? 0.25 : 0.08;

    return StreamBuilder<DateTime>(
      stream: timeStream,
      builder: (context, snapshot) {
        final timeToDisplay = snapshot.data ?? DateTime.now().toUtc().add(const Duration(hours: 8));
        final String formattedTime = DateFormat('hh:mm:ss a').format(timeToDisplay);
        final String formattedDate = DateFormat('EEE, MMM dd, yyyy').format(timeToDisplay);

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(shadowOpacity),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                "$formattedDate (PST)",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
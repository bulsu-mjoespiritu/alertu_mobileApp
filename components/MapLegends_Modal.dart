import 'package:flutter/material.dart';

class MapLegendsModal extends StatelessWidget {
  const MapLegendsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dark / Light Mode adaptive palette
    final containerBg = isDark
        ? const Color(0xFF1E293B).withOpacity(0.95)
        : Colors.white.withOpacity(0.95);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final headerTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF0A0A0A);
    final chipTextColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x66000000) : const Color(0x19000000),
              blurRadius: 10,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
            BoxShadow(
              color: isDark ? const Color(0x80000000) : const Color(0x19000000),
              blurRadius: 25,
              offset: const Offset(0, 20),
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Label
            Text(
              'MAP LEGENDS',
              style: TextStyle(
                color: headerTextColor,
                fontSize: 10,
                fontFamily: 'Public Sans',
                fontWeight: FontWeight.w700,
                height: 1.50,
                letterSpacing: 0.50,
              ),
            ),
            const SizedBox(height: 12),

            // Horizontal scrollable tags for small screens or tight spaces
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildLegendChip(
                    label: 'Fire',
                    assetPath: 'images/markerlegends/firemap.png',
                    bgColor: isDark ? const Color(0x4DDC2626) : const Color(0x33EF4444),
                    borderColor: const Color(0xFFEF4444),
                    textColor: chipTextColor,
                    fontFamily: 'Public Sans',
                  ),
                  const SizedBox(width: 8),
                  _buildLegendChip(
                    label: 'Flood',
                    assetPath: 'images/markerlegends/floodmap.png',
                    bgColor: isDark ? const Color(0x4D1D4ED8) : const Color(0x333B82F6),
                    borderColor: const Color(0xFF3B82F6),
                    textColor: chipTextColor,
                    fontFamily: 'Public Sans',
                  ),
                  const SizedBox(width: 8),
                  _buildLegendChip(
                    label: 'Accident',
                    assetPath: 'images/markerlegends/accmap.png',
                    bgColor: isDark ? const Color(0x4DA855F7) : const Color(0x33800080),
                    borderColor: isDark ? const Color(0xFFA855F7) : const Color(0xFF800080),
                    textColor: chipTextColor,
                    fontFamily: 'Inter',
                  ),
                  const SizedBox(width: 8),
                  _buildLegendChip(
                    label: 'Others',
                    assetPath: 'images/markerlegends/warnmap.png',
                    bgColor: isDark ? const Color(0x4DC2410C) : const Color(0x33F97316),
                    borderColor: const Color(0xFFF97316),
                    textColor: chipTextColor,
                    fontFamily: 'Inter',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Reusable Pill / Chip Builder
  Widget _buildLegendChip({
    required String label,
    required String assetPath,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required String fontFamily,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: bgColor,
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 1, color: borderColor),
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            assetPath,
            width: 20,
            height: 20,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: borderColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w600,
              height: 1.33,
            ),
          ),
        ],
      ),
    );
  }
}
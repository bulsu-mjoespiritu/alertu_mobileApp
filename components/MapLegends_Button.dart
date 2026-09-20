// lib/components/MapLegends_Button.dart
import 'package:flutter/material.dart';

class MapLegendsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MapLegendsButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF159879),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          onPressed: onPressed,
          iconSize: 24,
          icon: Image.asset(
            'images/markerlegends/maplegicon.png',
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.map_outlined,
              color: Color(0xFF3B82F6),
            ),
          ),
        ),
      ),
    );
  }
}
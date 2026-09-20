import 'package:flutter/material.dart';

class OptionItem {
  final IconData icon;
  final String label;
  final VoidCallback onClick;
  final Color color;
  final Widget? trailing;

  const OptionItem({
    required this.icon,
    required this.label,
    required this.onClick,
    required this.color,
    this.trailing,
  });
}
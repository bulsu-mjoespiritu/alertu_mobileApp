import 'package:flutter/material.dart';

class SwitchToReportModalCard extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const SwitchToReportModalCard({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Custom transition builder to slide components in as they fade
      transitionBuilder: (Widget child, Animation<double> animation) {
        final isEntering = child.key == const ValueKey('EnteringCard') || true;

        final offsetTween = isEntering
            ? Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero)
            : Tween<Offset>(begin: const Offset(0.0, -0.2), end: Offset.zero);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetTween.animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
import 'package:flutter/material.dart';
// 🛡️ FIX: Points directly to your Agora engine screen context file
import 'package:alertu_flutter/emergencycall_page.dart';

class EmergencyCallButton extends StatelessWidget {
  final String targetRoom;
  final String callerName;
  final String citizenId;

  const EmergencyCallButton({
    super.key,
    this.targetRoom = "admins",
    required this.callerName,
    required this.citizenId,
  });

  void _showSlideToCallModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // Dynamic theme colors
        final modalBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
        final dragHandleColor = isDark ? theme.colorScheme.outline.withOpacity(0.4) : const Color(0xFFCBD5E1);
        final titleColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
        final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);

        return Container(
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              // Adds extra spacing above bottom navigation bar
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom + 16
                    : 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle bar
                  Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: dragHandleColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  Text(
                    "Emergency Video Call",
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Slide to connect directly to emergency services",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Embedded Slide Control
                  _SlideToCallSlider(
                    targetRoom: targetRoom,
                    callerName: callerName,
                    citizenId: citizenId,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFDC2626),
      elevation: 6,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showSlideToCallModal(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: const Icon(
            Icons.phone_in_talk,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

// Internal Slider Widget
class _SlideToCallSlider extends StatefulWidget {
  final String targetRoom;
  final String callerName;
  final String citizenId;

  const _SlideToCallSlider({
    required this.targetRoom,
    required this.callerName,
    required this.citizenId,
  });

  @override
  State<_SlideToCallSlider> createState() => _SlideToCallSliderState();
}

class _SlideToCallSliderState extends State<_SlideToCallSlider> {
  double _dragPosition = 0.0;
  static const double _buttonHeight = 60.0;
  static const double _thumbSize = 52.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme adaptive colors
    final trackBg = isDark
        ? const Color(0xFF450A0A) // Dark red in dark mode
        : const Color(0xFFFFEBEE); // Light soft red in light mode

    final trackBorder = isDark
        ? const Color(0xFF7F1D1D)
        : const Color(0xFFFFCDD2);

    final fillProgressColor = isDark
        ? const Color(0xFF991B1B).withOpacity(0.6)
        : const Color(0xFFEF5350).withOpacity(0.3);

    final thumbColor = isDark
        ? const Color(0xFFDC2626) // Bright red thumb for dark mode
        : const Color(0xFFD32F2F); // Rich red thumb for light mode

    final textColor = isDark
        ? Colors.white
        : const Color(0xFFB71C1C); // Bold readable red for light mode

    final iconColor = isDark
        ? Colors.white70
        : const Color(0xFFC62828);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - _thumbSize - 8.0;

        return Container(
          height: _buttonHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(_buttonHeight / 2),
            border: Border.all(color: trackBorder, width: 1.5),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Active Progress Fill
              Container(
                width: (_dragPosition + _thumbSize).clamp(_thumbSize, constraints.maxWidth),
                height: _buttonHeight,
                decoration: BoxDecoration(
                  color: fillProgressColor,
                  borderRadius: BorderRadius.circular(_buttonHeight / 2),
                ),
              ),

              // Text Hint
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "SLIDE TO CALL",
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: iconColor,
                      size: 14,
                    ),
                  ],
                ),
              ),

              // Sliding Thumb
              Positioned(
                left: 4.0 + _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0) _dragPosition = 0;
                      if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_dragPosition >= maxDrag * 0.85) {
                      setState(() {
                        _dragPosition = maxDrag;
                      });

                      // Dismiss bottom sheet safely
                      Navigator.pop(context);

                      // Generate a unique channel name per call
                      final String uniqueChannelName =
                          'EMERGENCY_${DateTime.now().millisecondsSinceEpoch}';

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AgoraCallScreen(
                            channelName: uniqueChannelName,
                            callerName: widget.callerName,
                          ),
                        ),
                      );
                    } else {
                      // Reset position
                      setState(() {
                        _dragPosition = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone_in_talk,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
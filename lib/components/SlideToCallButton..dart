import 'package:flutter/material.dart';
import 'package:alertu_flutter/emergencycall_page.dart'; // Import your video call screen

class SlideToCallButton extends StatefulWidget {
  final String targetRoom;
  final String callerName;

  const SlideToCallButton({
    super.key,
    required this.targetRoom,
    this.callerName = "Emergency Responder",
  });

  @override
  State<SlideToCallButton> createState() => _SlideToCallButtonState();
}

class _SlideToCallButtonState extends State<SlideToCallButton> {
  double _dragPosition = 0.0;
  static const double _buttonHeight = 60.0;
  static const double _thumbSize = 52.0;
  bool _isTriggered = false; // Prevents double navigation fires during drag updates

  void _navigateToCallScreen(BuildContext context) {
    if (_isTriggered) return;
    setState(() {
      _isTriggered = true;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgoraCallScreen(
          channelName: widget.targetRoom,   // or generate a unique one
          callerName: widget.callerName,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _dragPosition = 0.0;
          _isTriggered = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Check current system brightness mode
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 2. Define theme colors dynamically based on Light vs Dark Mode
    final Color modalBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color dragHandleColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

    final Color trackBg = isDark
        ? const Color(0xFF450A0A) // Dark red background in dark mode
        : const Color(0xFFFFEBEE); // Soft, clean light red background in light mode

    final Color trackBorder = isDark
        ? const Color(0xFF7F1D1D)
        : const Color(0xFFFFCDD2);

    final Color fillProgressColor = isDark
        ? const Color(0xFF991B1B).withOpacity(0.6)
        : const Color(0xFFEF5350).withOpacity(0.3);

    final Color thumbColor = isDark
        ? const Color(0xFFDC2626) // Vivid red thumb for dark mode
        : const Color(0xFFD32F2F); // Rich red thumb for light mode

    final Color textColor = isDark
        ? Colors.white
        : const Color(0xFFB71C1C); // Dark red readable text for light mode

    final Color iconColor = isDark
        ? Colors.white70
        : const Color(0xFFC62828);

    return Container(
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // Adds bottom spacing above the phone's navigation bar
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Modal Drag Handle
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: dragHandleColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              // Slide Button Widget
              LayoutBuilder(
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
                        // 1. Sliding Background Progress Track
                        Container(
                          width: _dragPosition + _thumbSize,
                          height: _buttonHeight,
                          decoration: BoxDecoration(
                            color: fillProgressColor,
                            borderRadius: BorderRadius.circular(_buttonHeight / 2),
                          ),
                        ),

                        // 2. Centered Hint Text
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "SLIDE TO EMERGENCY CALL",
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

                        // 3. Draggable Thumb Button
                        Positioned(
                          left: 4.0 + _dragPosition,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              if (_isTriggered) return;
                              setState(() {
                                _dragPosition += details.delta.dx;
                                if (_dragPosition < 0) _dragPosition = 0;
                                if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                              });
                            },
                            onHorizontalDragEnd: (details) {
                              if (_isTriggered) return;

                              if (_dragPosition >= maxDrag * 0.85) {
                                // Lock thumb to the right side and route immediately
                                setState(() {
                                  _dragPosition = maxDrag;
                                });
                                _navigateToCallScreen(context);
                              } else {
                                // Snap back smoothly if released early
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
                                Icons.phone_forwarded_rounded,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
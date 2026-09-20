import 'package:floating_bubble_overlay/floating_bubble_overlay.dart';
import 'package:floating_bubble_overlay/src/models/models.dart';
import 'package:floating_bubble_overlay/src/enums/enums.dart';
import 'package:flutter/foundation.dart';

class BubbleService {
  /// Start the system floating icon bubble
  static Future<void> startBubble() async {
    try {
      // 1. Check for permission
      final bool hasPermission =
      await FloatingBubbleOverlay.instance.hasOverlayPermission();

      if (!hasPermission) {
        debugPrint('⚠️ Overlay permission not granted. Requesting...');
        await FloatingBubbleOverlay.instance.requestOverlayPermission();
      }

      // 2. Start bubble using instance and BubbleOptions model
      await FloatingBubbleOverlay.instance.startBubble(
        bubbleOptions: BubbleOptions(
          bubbleSize: 60,
          opacity: 0.9,
          enableClose: true,
          closeBehavior: CloseBehavior.following,
        ),
      );

      debugPrint('🫧 Floating bubble started successfully.');
    } catch (e) {
      debugPrint('❌ Error starting bubble: $e');
    }
  }

  /// Remove the floating bubble when returning to full screen or ending call
  static Future<void> stopBubble() async {
    try {
      await FloatingBubbleOverlay.instance.stopBubble();
      debugPrint('🔕 Floating bubble removed.');
    } catch (e) {
      debugPrint('❌ Error stopping bubble: $e');
    }
  }
}
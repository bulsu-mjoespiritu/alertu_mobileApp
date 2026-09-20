import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class CallRingtoneService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlaying = false;

  /// Starts the call ringtone
  static Future<void> startRingtone() async {
    if (_isPlaying) return;
    try {
      _isPlaying = true;

      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);

      // 💡 Tell AudioCache not to prepend 'assets/'
      _audioPlayer.audioCache.prefix = '';

      // Matches '- images/callringtone.mp3' in pubspec.yaml
      debugPrint('🔔 Playing call ringtone from: images/callringtone.mp3');
      await _audioPlayer.play(AssetSource('images/callringtone.mp3'));

      debugPrint('🔔 Call ringtone started successfully.');
    } catch (e, stack) {
      _isPlaying = false;
      debugPrint('❌ Error playing call ringtone: $e');
      debugPrint('❌ StackTrace: $stack');
    }
  }

  /// Stops the ringtone immediately
  static Future<void> stopRingtone() async {
    if (!_isPlaying) return;
    try {
      _isPlaying = false;
      await _audioPlayer.stop();
      debugPrint('🔕 Call ringtone stopped.');
    } catch (e) {
      debugPrint('❌ Error stopping call ringtone: $e');
    }
  }

  /// Free player resources
  static void dispose() {
    stopRingtone();
    _audioPlayer.dispose();
  }
}
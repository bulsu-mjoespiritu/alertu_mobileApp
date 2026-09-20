import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class RingtoneService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlaying = false;

  /// Starts the missed call ringtone (plays once without looping)
  static Future<void> startRingtone() async {
    if (_isPlaying) return;
    try {
      _isPlaying = true;

      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);

      // 💡 Changed from ReleaseMode.loop to ReleaseMode.stop so it won't repeat
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      // Tell AudioCache not to prepend 'assets/'
      _audioPlayer.audioCache.prefix = '';

      debugPrint('🔔 Playing missed call ringtone from: images/missedcallring.mp3');
      await _audioPlayer.play(AssetSource('images/missedcallring.mp3'));

      debugPrint('🔔 Missed call ringtone started successfully.');
    } catch (e, stack) {
      _isPlaying = false;
      debugPrint('❌ Error playing ringtone: $e');
      debugPrint('❌ StackTrace: $stack');
    }
  }

  /// Stops the ringtone immediately
  static Future<void> stopRingtone() async {
    if (!_isPlaying) return;
    try {
      _isPlaying = false;
      await _audioPlayer.stop();
      debugPrint('🔕 Ringtone stopped.');
    } catch (e) {
      debugPrint('❌ Error stopping ringtone: $e');
    }
  }

  /// Free player resources
  static void dispose() {
    stopRingtone();
    _audioPlayer.dispose();
  }
}
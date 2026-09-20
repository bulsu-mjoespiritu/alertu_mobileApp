import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class MessageToneService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlaying = false;

  /// Plays the message alert sound once (no looping)
  static Future<void> playMessageTone() async {
    if (_isPlaying) return;
    try {
      _isPlaying = true;

      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      // Tell AudioCache not to prepend 'assets/'
      _audioPlayer.audioCache.prefix = '';

      // Matches '- images/messagetone.mp3' in pubspec.yaml
      debugPrint('🔔 Playing message tone from: images/messagetone.mp3');
      await _audioPlayer.play(AssetSource('images/messagetone.mp3'));

      // Reset state automatically when playback completes
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlaying = false;
      });

      debugPrint('🔔 Message tone played successfully.');
    } catch (e, stack) {
      _isPlaying = false;
      debugPrint('❌ Error playing message tone: $e');
      debugPrint('❌ StackTrace: $stack');
    }
  }

  /// Stops the message tone immediately
  static Future<void> stopMessageTone() async {
    if (!_isPlaying) return;
    try {
      _isPlaying = false;
      await _audioPlayer.stop();
      debugPrint('🔕 Message tone stopped.');
    } catch (e) {
      debugPrint('❌ Error stopping message tone: $e');
    }
  }

  /// Free player resources
  static void dispose() {
    stopMessageTone();
    _audioPlayer.dispose();
  }
}
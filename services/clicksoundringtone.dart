import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class ClickSoundRingtoneService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static bool _isPlaying = false;

  /// Plays the click sound once (no looping)
  static Future<void> playClickSound() async {
    if (_isPlaying) return;
    try {
      _isPlaying = true;

      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);

      // Tell AudioCache not to prepend 'assets/'
      _audioPlayer.audioCache.prefix = '';

      // Matches '- images/clicksound.mp3' in pubspec.yaml
      debugPrint('🔔 Playing click sound from: images/clicksound.mp3');
      await _audioPlayer.play(AssetSource('images/clicksound.mp3'));

      // Reset state automatically when playback completes
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlaying = false;
      });

      debugPrint('🔔 Click sound played successfully.');
    } catch (e, stack) {
      _isPlaying = false;
      debugPrint('❌ Error playing click sound: $e');
      debugPrint('❌ StackTrace: $stack');
    }
  }

  /// Stops the click sound immediately
  static Future<void> stopClickSound() async {
    if (!_isPlaying) return;
    try {
      _isPlaying = false;
      await _audioPlayer.stop();
      debugPrint('🔕 Click sound stopped.');
    } catch (e) {
      debugPrint('❌ Error stopping click sound: $e');
    }
  }

  /// Free player resources
  static void dispose() {
    stopClickSound();
    _audioPlayer.dispose();
  }
}
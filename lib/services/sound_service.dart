import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Plays cozy offline sound effects and subtle phone vibrations for game events.
class SoundService {
  SoundService({this.enabled = true});

  bool enabled;

  // Separate lightweight players so rapid ticks don't cut off celebration chimes.
  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _fxPlayer = AudioPlayer();

  void setEnabled(bool value) {
    enabled = value;
  }

  /// Ultra-soft 25ms pencil/tick tap + tiny micro-tick vibration as finger glides.
  Future<void> playLetterTick() async {
    await HapticFeedback.selectionClick();
    await _playAsset(_tickPlayer, 'sounds/letter_tick.wav', volume: 0.45);
  }

  /// Warm acoustic chime + light satisfying pulse when a valid word is found.
  Future<void> playWordFound() async {
    await HapticFeedback.lightImpact();
    await _playAsset(_fxPlayer, 'sounds/word_found.wav', volume: 0.85);
  }

  /// Gentle muted low tap with no vibration when an invalid swipe is released.
  Future<void> playWrongSwipe() async {
    await _playAsset(_fxPlayer, 'sounds/wrong_swipe.wav', volume: 0.5);
  }

  /// Soft sparkle chime + light tap when Hint Bulb highlights a letter.
  Future<void> playHintSparkle() async {
    await HapticFeedback.lightImpact();
    await _playAsset(_fxPlayer, 'sounds/hint_sparkle.wav', volume: 0.85);
  }

  /// Cheerful 4-note acoustic fanfare + celebration double-tap on level finish.
  Future<void> playLevelComplete() async {
    await HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 120), () {
      HapticFeedback.mediumImpact();
    });
    await _playAsset(_fxPlayer, 'sounds/level_complete.wav', volume: 0.9);
  }

  Future<void> _playAsset(
    AudioPlayer player,
    String assetPath, {
    required double volume,
  }) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Ignore audio plugin errors in headless test environments.
    }
  }

  Future<void> dispose() async {
    await _tickPlayer.dispose();
    await _fxPlayer.dispose();
  }
}

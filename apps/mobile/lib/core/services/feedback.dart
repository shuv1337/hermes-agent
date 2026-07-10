import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Desktop-parity haptic intents (see apps/desktop/src/lib/haptics.ts).
enum HapticIntent {
  cancel,
  close,
  crisp,
  error,
  open,
  selection,
  streamDone,
  streamStart,
  submit,
  success,
  tap,
  warning,
}

/// Haptics + soft UI sounds + agent-turn completion chime.
///
/// Mirrors Desktop: one mute flag gates **both** haptics and completion sound
/// (`$hapticsMuted` / titlebar mute). Preview APIs ignore mute so Settings
/// can audition while muted.
class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  final AudioPlayer _player = AudioPlayer();
  bool muted = false;

  DateTime _lastSelectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _recentFires = [];

  static const _rateWindow = Duration(seconds: 1);
  static const _rateLimit = 5;

  /// Fire a haptic (+ optional system click for light intents).
  void trigger(HapticIntent intent) {
    if (muted) return;
    if (!_allowFire(intent)) return;
    unawaited(_runHaptic(intent));
    if (intent == HapticIntent.selection || intent == HapticIntent.tap) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
  }

  /// Agent turn finished — haptic pattern + completion chime (Desktop streamDone).
  void streamDone() {
    if (muted) return;
    if (!_allowFire(HapticIntent.streamDone)) return;
    unawaited(_runHaptic(HapticIntent.streamDone));
    unawaited(playCompletionSound());
  }

  /// Soft error cue.
  void error() {
    if (muted) return;
    if (!_allowFire(HapticIntent.error)) return;
    unawaited(_runHaptic(HapticIntent.error));
    unawaited(SystemSound.play(SystemSoundType.alert));
  }

  /// Settings audition — always plays, even when muted.
  Future<void> preview() async {
    await _runHaptic(HapticIntent.success);
    await playCompletionSound(force: true);
  }

  Future<void> playCompletionSound({bool force = false}) async {
    if (muted && !force) return;
    try {
      // Desktop default "Two-note comfort" (E4 then C4) as a short PCM WAV.
      final wav = _twoNoteComfortWav();
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      debugPrint('Feedback: completion sound failed: $e');
    }
  }

  bool _allowFire(HapticIntent intent) {
    final now = DateTime.now();
    if (intent == HapticIntent.selection) {
      if (now.difference(_lastSelectionAt) < const Duration(milliseconds: 50)) {
        return false;
      }
      _lastSelectionAt = now;
    }
    _recentFires.removeWhere((t) => now.difference(t) > _rateWindow);
    if (_recentFires.length >= _rateLimit) return false;
    _recentFires.add(now);
    return true;
  }

  Future<void> _runHaptic(HapticIntent intent) async {
    try {
      switch (intent) {
        case HapticIntent.selection:
        case HapticIntent.tap:
        case HapticIntent.streamStart:
          await HapticFeedback.selectionClick();
        case HapticIntent.crisp:
        case HapticIntent.open:
        case HapticIntent.close:
          await HapticFeedback.lightImpact();
        case HapticIntent.submit:
        case HapticIntent.success:
        case HapticIntent.streamDone:
          await HapticFeedback.mediumImpact();
          // Soft double-tap (Desktop friendlySuccess / submit has two pulses).
          await Future<void>.delayed(const Duration(milliseconds: 48));
          await HapticFeedback.lightImpact();
        case HapticIntent.cancel:
        case HapticIntent.warning:
          await HapticFeedback.mediumImpact();
        case HapticIntent.error:
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 42));
          await HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Feedback: haptic failed: $e');
    }
  }

  /// PCM WAV: E4 (329.63 Hz) then C4 (261.63 Hz) — Desktop variant 1.
  static Uint8List _twoNoteComfortWav() {
    const sampleRate = 22050;
    const channels = 1;
    const bitsPerSample = 16;
    final samples = <int>[];

    void tone({
      required double freq,
      required double startSec,
      required double durSec,
      required double peak,
      double attack = 0.03,
    }) {
      final start = (startSec * sampleRate).round();
      final n = (durSec * sampleRate).round();
      final attackN = math.max(1, (attack * sampleRate).round());
      while (samples.length < start + n) {
        samples.add(0);
      }
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final env = i < attackN
            ? (i / attackN)
            : math.exp(-3.2 * (i - attackN) / (n - attackN + 1));
        final s = math.sin(2 * math.pi * freq * t) * peak * env;
        final idx = start + i;
        final mixed = (samples[idx] / 32767.0) + s;
        samples[idx] = (mixed.clamp(-1.0, 1.0) * 32767).round().clamp(
          -32768,
          32767,
        );
      }
    }

    // E4 then overlapping C4 (Desktop two-note comfort, quieter for phone).
    tone(freq: 329.63, startSec: 0.0, durSec: 0.22, peak: 0.28, attack: 0.03);
    tone(freq: 261.63, startSec: 0.08, durSec: 0.52, peak: 0.34, attack: 0.08);
    tone(freq: 130.81, startSec: 0.08, durSec: 0.46, peak: 0.12, attack: 0.1);

    final dataSize = samples.length * 2;
    final bytes = BytesBuilder();
    void writeStr(String s) => bytes.add(s.codeUnits);
    void write32(int v) {
      bytes.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
    }

    void write16(int v) {
      bytes.add([v & 0xff, (v >> 8) & 0xff]);
    }

    writeStr('RIFF');
    write32(36 + dataSize);
    writeStr('WAVE');
    writeStr('fmt ');
    write32(16);
    write16(1); // PCM
    write16(channels);
    write32(sampleRate);
    write32(sampleRate * channels * bitsPerSample ~/ 8);
    write16(channels * bitsPerSample ~/ 8);
    write16(bitsPerSample);
    writeStr('data');
    write32(dataSize);
    for (final s in samples) {
      write16(s);
    }
    return bytes.toBytes();
  }
}

/// Shortcut for UI call sites.
void hermesHaptic(HapticIntent intent) =>
    FeedbackService.instance.trigger(intent);

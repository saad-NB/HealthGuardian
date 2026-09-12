import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/heart_rate/ppg_pipeline.dart';
import 'package:healthguardian/vitals/models.dart';

/// Synthesises a PPG-like red-channel signal: pulsatile sine on a bright
/// baseline with drift and optional noise.
///
/// [bpm] heart rate, [durationSeconds] length, [sampleRateHz] cadence.
List<(double ms, double red)> synthPpg({
  required double bpm,
  required double durationSeconds,
  double sampleRateHz = 30,
  double amplitude = 1.5,
  double noise = 0.0,
  int seed = 1,
  double baseline = 110,
}) {
  final rng = math.Random(seed);
  final out = <(double, double)>[];
  final total = (durationSeconds * sampleRateHz).round();
  final msPerFrame = 1000 / sampleRateHz;
  for (var i = 0; i < total; i++) {
    final t = i / sampleRateHz;
    final pulse = amplitude * math.sin(2 * math.pi * bpm / 60 * t);
    final drift = 3 * math.sin(2 * math.pi * 0.05 * t); // slow wander
    final n = noise * (rng.nextDouble() * 2 - 1);
    out.add((
      i * msPerFrame,
      baseline + pulse + drift + n,
    ));
  }
  return out;
}

PpgPipeline feed(
  List<(double, double)> samples, {
  PpgConfig config = const PpgConfig(),
}) {
  final p = PpgPipeline(config: config);
  for (final (ms, red) in samples) {
    p.add(timestampMs: ms, redMean: red);
  }
  return p;
}

// Config shortened so headless tests stay fast.
const shortConfig = PpgConfig(minUsableSeconds: 8, earlyFinishUsableSeconds: 6);

void main() {
  group('PpgPipeline accuracy', () {
    test('recovers ~100 bpm from a clean 15s waveform', () {
      final p =
          feed(synthPpg(bpm: 100, durationSeconds: 15), config: shortConfig);
      expect(p.hasBeat, isTrue);
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.bpm, closeTo(100, 4));
      expect(est.usableSeconds, greaterThanOrEqualTo(8));
      expect(est.confidence, isNot(ReadingConfidence.low));
    });

    test('recovers ~70 bpm (low end of band)', () {
      final p =
          feed(synthPpg(bpm: 70, durationSeconds: 15), config: shortConfig);
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.bpm, closeTo(70, 4));
    });

    test('recovers ~180 bpm (high end of band)', () {
      final p =
          feed(synthPpg(bpm: 180, durationSeconds: 15), config: shortConfig);
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.bpm, closeTo(180, 8));
    });

    test('noise degrades the rhythm → confidence stays low (or honest null)',
        () {
      final p = feed(
        synthPpg(bpm: 100, durationSeconds: 15, amplitude: 0.4, noise: 2.5),
        config: shortConfig,
      );
      final est = p.estimate();
      // The pipeline must never hand back a confident reading for noise: it
      // either says "low confidence" or refuses an estimate entirely.
      final honest =
          est == null || est.confidence == ReadingConfidence.low;
      expect(honest, isTrue, reason: 'est was $est');
    });

    test('below-band signal (30 bpm) never estimate-hypes a wrong number', () {
      // 30 bpm is below the 42 bpm low edge: the pulse is outside the
      // band-pass, so peaks must not produce a confident cadence.
      final p = feed(
        synthPpg(bpm: 30, durationSeconds: 20, amplitude: 3),
        config: shortConfig,
      );
      final est = p.estimate();
      if (est != null) {
        expect(est.confidence, ReadingConfidence.low);
      }
      expect(p.earlyFinishEligible(), isFalse);
    });

    test('earlyFinishEligible gates on usable coverage + quality', () {
      final p =
          feed(synthPpg(bpm: 100, durationSeconds: 20), config: shortConfig);
      expect(p.earlyFinishEligible(), isTrue);
    });

    test(
        'registers a medium estimate when autocorrelation can or cannot '
        'confirm a period', () {
      // minAutocorrelation = 2.0 forces dominantPeriod() to always fail, so
      // the peak-cadence fallback must carry a clean regular beat train
      // through instead of refusing the estimate ("not enough signal").
      final p = feed(
        synthPpg(bpm: 100, durationSeconds: 20),
        config: const PpgConfig(
          minUsableSeconds: 8,
          earlyFinishUsableSeconds: 6,
          minAutocorrelation: 2.0,
        ),
      );
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.bpm, closeTo(100, 5));
      expect(est.confidence, isNot(ReadingConfidence.low));
    });

    test('no autocorrelation fallback does not rescue a noisy train', () {
      final p = feed(
        synthPpg(
          bpm: 100,
          durationSeconds: 20,
          amplitude: 0.4,
          noise: 2.5,
        ),
        config: const PpgConfig(
          minUsableSeconds: 8,
          earlyFinishUsableSeconds: 6,
          minAutocorrelation: 2.0,
        ),
      );
      final est = p.estimate();
      final honest = est == null || est.confidence == ReadingConfidence.low;
      expect(honest, isTrue, reason: 'est was $est');
    });

    test('reset restores the fresh state', () {
      final p =
          feed(synthPpg(bpm: 100, durationSeconds: 15), config: shortConfig);
      p.reset();
      expect(p.hasBeat, isFalse);
      expect(p.estimate(), isNull);
      expect(p.usableSeconds, 0);
    });
  });
}
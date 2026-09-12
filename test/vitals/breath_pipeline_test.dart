import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/breathing_rate/breath_pipeline.dart';
import 'package:healthguardian/vitals/models.dart';

const _sampleRateHz = 16000.0;

/// Synthetic PCM: a 550 Hz carrier whose amplitude is a single-hump
/// breath-cycle envelope (one energy burst per breath at [cpm]; pass
/// [doubleBurst] for the inhale+exhale split structure), plus optional
/// broadband noise ([ambient]) and an out-of-band rumble tone ([lowFreqHz]).
Float64List synthBreath({
  required double cpm,
  required double seconds,
  double amplitude = 0.05,
  double carrierHz = 550,
  double lowFreqHz = 0,
  double ambient = 0,
  bool doubleBurst = false,
  int seed = 3,
}) {
  final n = (seconds * _sampleRateHz).round();
  final out = Float64List(n);
  final f = cpm / 60;
  final rng = math.Random(seed);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRateHz;
    final mod = 0.75 + 0.25 * math.sin(2 * math.pi * f * t);
    final env = amplitude * (doubleBurst ? mod * mod : mod);
    var v = math.sin(2 * math.pi * carrierHz * t) * env;
    if (lowFreqHz > 0) v += 0.06 * math.sin(2 * math.pi * lowFreqHz * t);
    if (ambient > 0) v += ambient * (rng.nextDouble() * 2 - 1);
    out[i] = v;
  }
  return out;
}

/// Synthetic PCM with two energy bursts per breath (inhale + exhale, unequal
/// and slightly noisy) — what a phone at the mouth/nose actually hears.
Float64List synthTwoBurstBreath({
  required double cpm,
  required double seconds,
  int seed = 5,
}) {
  final n = (seconds * _sampleRateHz).round();
  final out = Float64List(n);
  final f = cpm / 60;
  final rng = math.Random(seed);
  double bump(double phase, double c, double w) =>
      math.exp(-(((phase - c) / w) * ((phase - c) / w)));
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRateHz;
    final phase = (t * f) % 1.0;
    final env = 0.04 *
        (0.15 + 0.9 * bump(phase, 0.25, 0.10) + 0.6 * bump(phase, 0.70, 0.12));
    var v = math.sin(2 * math.pi * 550 * t) * env;
    v += 0.004 * (rng.nextDouble() * 2 - 1);
    out[i] = v;
  }
  return out;
}

void feed(BreathPipeline p, Float64List pcm,
    {int chunk = 2048, double startSeconds = 0}) {
  for (var off = 0; off < pcm.length; off += chunk) {
    final end = math.min(off + chunk, pcm.length);
    p.add(
      samples: Float64List.sublistView(pcm, off, end),
      elapsedSeconds: startSeconds + end / _sampleRateHz,
    );
  }
}

void main() {
  group('BreathPipeline', () {
    test('clean 15 cpm resolves to ~15 with usable coverage', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 15, seconds: 45));
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.cpm, closeTo(15, 2));
      expect(est.confidence, isNot(ReadingConfidence.low));
      expect(est.usableSeconds, greaterThanOrEqualTo(28));
    });

    test('startup silence does not poison the envelope (regression)', () {
      // Real captures begin with silent/zero frames. There env and detrend are
      // both 0, so env/det was NaN — and one NaN in the recursive envelope
      // filter's delay line produced zero peaks for the entire session no
      // matter how clean the breathing was.
      final p = BreathPipeline();
      feed(p, Float64List(_sampleRateHz.round())); // 1 s of silence
      feed(p, synthBreath(cpm: 15, seconds: 44), startSeconds: 1);
      expect(p.hasBreath, isTrue);
      expect(p.ibiCount, greaterThan(3));
      expect(p.qualityScore(), greaterThan(0.5));
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.cpm, closeTo(15, 3));
    });

    test('bradypneic 8 cpm still resolves', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 8, seconds: 45));
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.cpm, closeTo(8, 2));
    });

    test('tachypneic 36 cpm resolves within tolerance', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 36, seconds: 45));
      final est = p.estimate();
      expect(est, isNotNull);
      expect(est!.cpm, closeTo(36, 3));
    });

    test('inhale+exhale double bursts never fake a fast rate', () {
      // A squared envelope splits each breath into two energy crests. Real
      // breathing can do this too; the pipeline must reject the resulting
      // half-interval "tachypnea" rather than report a wrong strong number,
      // and it must not silence true bradypnea on a clean single-burst signal.
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 8, seconds: 45, doubleBurst: true));
      final est = p.estimate();
      if (est != null) {
        // Only a figure near the real rate survives the guard, never ~16.
        expect(est.cpm, closeTo(8, 2));
      }
    });

    test('two-burst breathing reports the breath rate, not the burst rate', () {
      // A phone at the mouth/nose hears an inhale and an exhale burst per
      // breath, so the raw peak cadence is ~2x the breath rate. The pipeline
      // must fold the subharmonic back down.
      for (final cpm in [10.0, 15.0, 18.0, 24.0, 27.0]) {
        final p = BreathPipeline();
        feed(p, synthTwoBurstBreath(cpm: cpm, seconds: 45));
        final est = p.estimate();
        expect(est, isNotNull);
        expect(est!.cpm, closeTo(cpm, 3));
      }
    });

    test('subharmonic ratio separates one-burst from two-burst envelopes', () {
      // One energy burst per breath: no envelope fundamental at half the peak
      // cadence, so the octave must not be doubled (the device bug where 30+
      // bpm read as ~13-14).
      final one = BreathPipeline();
      feed(one, synthBreath(cpm: 30, seconds: 45));
      expect(one.subharmonicRatio(), lessThan(0.05));

      // Two bursts per breath: a real envelope fundamental at half the peak
      // cadence proves the doubled period is the breath cycle.
      final two = BreathPipeline();
      feed(two, synthTwoBurstBreath(cpm: 27, seconds: 45));
      expect(two.subharmonicRatio(), greaterThan(0.08));
    });

    test('3 cpm is below band -> no estimate', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 3, seconds: 45));
      expect(p.estimate(), isNull);
    });

    test('quiet room without breath sounds -> no estimate', () {
      final p = BreathPipeline();
      // Near-silence: only the rng floor exists, so no envelope cycles.
      feed(p, synthBreath(cpm: 0, seconds: 20, amplitude: 1e-6, ambient: 2e-4));
      expect(p.estimate(), isNull);
    });

    test('loud room trips the ambient-noise gate', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 15, seconds: 30, ambient: 0.09));
      expect(p.ambientNoisy, isTrue);
      expect(p.estimate(), isNull);
    });

    test('sub-band rumble (2 Hz) is rejected, not read as slow breathing', () {
      final p = BreathPipeline();
      // Near-zero carrier so only the out-of-band rumble reaches the mic.
      feed(p, synthBreath(cpm: 0, seconds: 30, lowFreqHz: 2, amplitude: 1e-6));
      expect(p.subBandDominant, isTrue);
      expect(p.estimate(), isNull);
    });

    test('early finish becomes eligible on a stable clean signal', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 15, seconds: 20));
      expect(p.earlyFinishEligible(), isFalse); // not enough usable coverage
      feed(p, synthBreath(cpm: 15, seconds: 25), startSeconds: 20);
      expect(p.earlyFinishEligible(), isTrue);
    });

    test('reset clears estimate state', () {
      final p = BreathPipeline();
      feed(p, synthBreath(cpm: 15, seconds: 40));
      expect(p.estimate(), isNotNull);
      p.reset();
      expect(p.estimate(), isNull);
      expect(p.earlyFinishEligible(), isFalse);
      expect(p.hasBreath, isFalse);
    });
  });
}
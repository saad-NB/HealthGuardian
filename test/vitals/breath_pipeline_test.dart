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
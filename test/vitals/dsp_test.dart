import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/dsp/biquad.dart';
import 'package:healthguardian/vitals/dsp/fft.dart';
import 'package:healthguardian/vitals/dsp/movavg.dart';
import 'package:healthguardian/vitals/dsp/peak_detect.dart';
import 'package:healthguardian/vitals/dsp/rms.dart';
import 'package:healthguardian/vitals/dsp/spectral_denoise.dart';
import 'package:healthguardian/vitals/dsp/window.dart';

void main() {
  group('MovingAverage', () {
    test('returns null until the window fills', () {
      final ma = MovingAverage(3);
      expect(ma.update(1), isNull);
      expect(ma.update(2), isNull);
      final value = ma.update(3);
      expect(value, closeTo(2, 1e-9));
      expect(ma.value, closeTo(2, 1e-9));
    });

    test('slides as new samples arrive', () {
      final ma = MovingAverage(3);
      ma.update(1);
      ma.update(2);
      ma.update(3);
      expect(ma.update(4), closeTo(3, 1e-9));
      expect(ma.update(5), closeTo(4, 1e-9));
    });

    test('a flat signal average equals that constant', () {
      final ma = MovingAverage(4);
      for (var i = 0; i < 10; i++) {
        ma.update(7);
      }
      expect(ma.value, closeTo(7, 1e-9));
    });
  });

  group('Rms', () {
    test('returns null until the window fills', () {
      final rms = Rms(3);
      expect(rms.update(2), isNull);
      expect(rms.update(2), isNull);
      expect(rms.update(2), closeTo(2, 1e-9));
    });

    test('dc component is preserved under sqrt mean square', () {
      final rms = Rms(2);
      rms.update(4);
      expect(rms.update(4), closeTo(4, 1e-9));
      expect(rms.update(0), closeTo(2.8284, 1e-2));
    });

    test('slides correctly', () {
      final rms = Rms(2);
      rms.update(3);
      final v = rms.update(4);
      expect(v, closeTo(math.sqrt((9 + 16) / 2), 1e-9));
      expect(rms.update(0), closeTo(math.sqrt(16 / 2), 1e-9));
    });
  });

  group('Biquad low-pass', () {
    /// Steady-state output amplitude for a sine of [freqHz], after transients
    /// die out (the measured gain of the filter at that frequency).
    double toneAmplitude(
      Biquad b,
      double freqHz, {
      int sampleRate = 30,
      int settle = 400,
      int measure = 90,
    }) {
      final omega = 2 * math.pi * freqHz;
      for (var i = 0; i < settle; i++) {
        b.process(math.sin(omega * i / sampleRate));
      }
      var lo = 1e9, hi = -1e9;
      for (var i = 0; i < measure; i++) {
        final y = b.process(math.sin(omega * i / sampleRate));
        if (y < lo) lo = y;
        if (y > hi) hi = y;
      }
      return (hi - lo) / 2;
    }

    test('passes DC (constant input) at unity gain', () {
      final lp = Biquad.lowPass(cutoffHz: 2, sampleRateHz: 30);
      double last = 0;
      for (var i = 0; i < 300; i++) {
        last = lp.process(1);
      }
      expect(last, closeTo(1, 0.01));
    });

    test('attenuates a tone well above cutoff', () {
      final lp = Biquad.lowPass(cutoffHz: 1, sampleRateHz: 30);
      expect(toneAmplitude(lp, 1), greaterThan(0.5)); // near cutoff
      expect(toneAmplitude(lp, 10), lessThan(0.1)); // 10 Hz far above
    });

    test('band-pass admits its center tone and blocks distant ones', () {
      final bp = Biquad.bandPass(centerHz: 1.2, sampleRateHz: 30, q: 1.5);
      expect(toneAmplitude(bp, 1.2), greaterThan(0.7)); // pass center
      expect(toneAmplitude(bp, 6), lessThan(0.2)); // far above
      expect(toneAmplitude(bp, 0.15), lessThan(0.25)); // far below
    });

    test('reset clears state', () {
      final lp = Biquad.lowPass(cutoffHz: 2, sampleRateHz: 30);
      for (var i = 0; i < 100; i++) {
        lp.process(100);
      }
      lp.reset();
      expect(lp.process(0), closeTo(0, 1e-9));
    });
  });

  group('PeakDetector', () {
    test('confirms each clean beat once, refractory enforced', () {
      final pd = PeakDetector(refractoryMs: 200, fallRatio: 0.25, minHeight: 0);
      final peaks = <double>[];
      // Two clean beats ≥ refractory apart.
      const beats = [
        (t: 100.0, v: 0), // baseline before beat 1
        (t: 120.0, v: 10), // peak 1
        (t: 140.0, v: 5),
        (t: 160.0, v: 2), // fall > 25% → completes at 120
        (t: 200.0, v: 0),
        (t: 420.0, v: 9), // peak 2 (300 ms after 120)
        (t: 440.0, v: 3),
        (t: 460.0, v: 1), // completes at 420
      ];
      for (final b in beats) {
        final p = pd.update(timestampMs: b.t, value: b.v.toDouble());
        if (p != null) peaks.add(p.timestampMs);
      }
      expect(peaks, [120.0, 420.0]);
      expect(pd.acceptedCount, 2);
    });

    test('small noise bumps never count as beats', () {
      final pd = PeakDetector(refractoryMs: 200, fallRatio: 0.25, minHeight: 5);
      for (var i = 0; i < 100; i++) {
        pd.update(timestampMs: i * 10.0, value: 1 + (i % 3));
      }
      expect(pd.acceptedCount, 0);
    });

    test('below minHeight peaks are rejected', () {
      final pd = PeakDetector(refractoryMs: 100, fallRatio: 0.5, minHeight: 8);
      final beats = [
        (t: 10.0, v: 5), // too small
        (t: 30.0, v: 2),
        (t: 60.0, v: 10), // tall enough
        (t: 80.0, v: 3),
      ];
      var accepted = 0;
      for (final b in beats) {
        final p = pd.update(timestampMs: b.t, value: b.v.toDouble());
        if (p != null) accepted++;
      }
      expect(accepted, 1);
    });
  });

  group('fft', () {
    test('forward + inverse round-trips a signal', () {
      final rng = math.Random(1);
      const n = 256;
      final re = Float64List(n);
      final im = Float64List(n);
      final orig = Float64List(n);
      for (var i = 0; i < n; i++) {
        orig[i] = rng.nextDouble() * 2 - 1;
        re[i] = orig[i];
      }
      fft(re, im);
      fft(re, im, inverse: true);
      for (var i = 0; i < n; i++) {
        expect(re[i], closeTo(orig[i], 1e-9));
        expect(im[i], closeTo(0, 1e-9));
      }
    });

    test('a pure tone concentrates at its bin', () {
      const n = 256;
      const sr = 256.0;
      const freq = 32.0; // exactly bin 32
      final re = Float64List(n);
      final im = Float64List(n);
      for (var i = 0; i < n; i++) {
        re[i] = math.sin(2 * math.pi * freq * i / sr);
      }
      fft(re, im);
      var bestK = 0;
      var bestMag = 0.0;
      for (var k = 1; k < n ~/ 2; k++) {
        final m = math.sqrt(re[k] * re[k] + im[k] * im[k]);
        if (m > bestMag) {
          bestMag = m;
          bestK = k;
        }
      }
      expect(bestK, 32);
    });
  });

  group('SpectralDenoiser', () {
    Float64List tone({
      required double seconds,
      double hz = 0,
      double amp = 0,
      double noise = 0,
      int seed = 1,
    }) {
      const sr = 16000.0;
      final n = (seconds * sr).round();
      final out = Float64List(n);
      final rng = math.Random(seed);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        var v = 0.0;
        if (hz > 0) v += amp * math.sin(2 * math.pi * hz * t);
        if (noise > 0) v += noise * (rng.nextDouble() * 2 - 1);
        out[i] = v;
      }
      return out;
    }

    double rms(Float64List x, [int skip = 0]) {
      var s = 0.0;
      var c = 0;
      for (var i = skip; i < x.length; i++) {
        s += x[i] * x[i];
        c++;
      }
      return math.sqrt(s / c);
    }

    test('has no profile (and passes audio through) before calibration', () {
      final d = SpectralDenoiser();
      expect(d.hasProfile, isFalse);
      final input = tone(seconds: 0.5, hz: 300, amp: 0.2);
      final out = d.process(input);
      expect(identical(out, input), isTrue);
    });

    test('learns a stationary tone and suppresses it', () {
      final d = SpectralDenoiser();
      d.calibrate(tone(seconds: 2, hz: 300, amp: 0.2, noise: 0.01));
      d.finalizeCalibration();
      expect(d.hasProfile, isTrue);
      expect(d.calibrationFrames, greaterThan(10));

      final input = tone(seconds: 1, hz: 300, amp: 0.2, noise: 0.01, seed: 2);
      final out = d.process(input);
      expect(out.length, input.length); // length preserved for timing
      expect(rms(out, 4000), lessThan(0.4 * rms(input, 4000)));
    });

    test('preserves a tone that was not present in the profile', () {
      final d = SpectralDenoiser();
      d.calibrate(tone(seconds: 2, hz: 300, amp: 0.2));
      d.finalizeCalibration();

      final input = tone(seconds: 1, hz: 550, amp: 0.2);
      final out = d.process(input);
      expect(rms(out, 4000), greaterThan(0.6 * rms(input, 4000)));
    });

    test('streaming chunks keep output aligned with input length', () {
      final d = SpectralDenoiser();
      d.calibrate(tone(seconds: 1, hz: 300, amp: 0.2));
      d.finalizeCalibration();

      final input = tone(seconds: 0.6, hz: 550, amp: 0.2);
      const chunk = 2048;
      var total = 0;
      for (var off = 0; off < input.length; off += chunk) {
        final end = math.min(off + chunk, input.length);
        final out =
            d.process(Float64List.sublistView(input, off, end));
        expect(out.length, end - off);
        total += out.length;
      }
      expect(total, input.length);
    });
  });

  group('TimestampedWindow', () {
    test('drops expired samples only on new additions', () {
      final w = TimestampedWindow(capacityMs: 100);
      w.add(1, timestampMs: 0);
      w.add(2, timestampMs: 40);
      expect(w.length, 2);
      w.add(3, timestampMs: 150); // 0 and 40 now expired
      expect(w.length, 1);
      expect(w.newestValue, 3);
    });

    test('countSince counts recent samples', () {
      final w = TimestampedWindow(capacityMs: 1000);
      w.add(1, timestampMs: 100);
      w.add(2, timestampMs: 200);
      w.add(3, timestampMs: 300);
      expect(w.countSince(250), 1);
      expect(w.countSince(100), 3);
    });

    test('rejects out-of-order timestamps', () {
      final w = TimestampedWindow(capacityMs: 1000);
      w.add(1, timestampMs: 100);
      expect(() => w.add(2, timestampMs: 50), throwsArgumentError);
    });
  });
}
import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/biquad.dart';
import '../dsp/movavg.dart';
import '../dsp/peak_detect.dart';
import '../dsp/rms.dart';
import '../dsp/window.dart';
import '../models.dart';

/// One live/final breathing-rate estimate.
class BreathEstimate {
  const BreathEstimate({
    required this.cpm,
    required this.confidence,
    this.usableSeconds = 0,
    this.note,
  });

  /// Breaths per minute.
  final double cpm;
  final ReadingConfidence confidence;
  final int usableSeconds;
  final String? note;
}

/// Tunable RR filtering/quality constants (VITALS_SENSING §5.2/§9.3 — any
/// change is a DECISIONS entry).
class BreathConfig {
  const BreathConfig({
    this.sampleRateHz = 16000,
    this.envelopeMs = 30,
    this.bandpassCenterHz = 550,
    this.bandpassQ = 0.6,
    this.cpmMin = 4,
    this.cpmMax = 60,
    this.detrendSeconds = 15,
    this.noiseFloorRms = 0.045,
    this.minUsableSeconds = 30,
    this.earlyFinishUsableSeconds = 28,
    this.maxIbiSeconds = 15,
    this.peakGapSeconds = 12,
    this.qualityHigh = 0.75,
    this.qualityMedium = 0.55,
    this.fallRatio = 0.35,
    this.minPeakRatio = 0.12,
    this.subBandRatioThreshold = 0.25,
    this.minAutocorrelation = 0.5,
    this.cadenceHarmonicTolerance = 0.3,
    this.minDominantCycles = 3,
    this.singleBurstCorrFloor = 0.95,
    this.minPairSwing = 0.12,
    this.subharmonicEnergyRatio = 0.08,
  });

  /// Microphone sample rate.
  final double sampleRateHz;

  /// Short-time RMS frame length (ms) — breath sounds appear as periodic
  /// energy bursts, so we work on the energy envelope, not the raw audio.
  final double envelopeMs;

  /// Center of the acoustic band-pass that rejects room noise/speech/Nyquist
  /// roll-off while keeping breath sounds (VITALS_SENSING §5.2).
  final double bandpassCenterHz;
  final double bandpassQ;

  /// Valid RR range (band edges, breaths/min).
  final double cpmMin;
  final double cpmMax;

  /// Envelope detrending moving-average length (seconds).
  final double detrendSeconds;

  /// Normalized-PCM ambient RMS above which the room is too loud to measure
  /// (talking, alarms) — the "please ensure quiet surroundings" gate.
  final double noiseFloorRms;

  /// Seconds of continuous usable envelope required before [estimate] can
  /// report anything but low confidence (RR is slower than HR, so this is
  /// longer than the HR constant).
  final int minUsableSeconds;

  /// The service may finish early once this many usable seconds exist.
  final int earlyFinishUsableSeconds;

  /// Max accepted inter-breath interval (seconds) — the low-cpm guard.
  final double maxIbiSeconds;

  /// A peak gap longer than this (seconds) resets "usable coverage" — the
  /// signal was lost, not just slow.
  final double peakGapSeconds;

  /// Quality-score thresholds for high/medium confidence.
  final double qualityHigh;
  final double qualityMedium;

  /// Fraction of the candidate peak the envelope must fall below it to confirm
  /// completion. RR valleys between breaths are deep; the small shoulders a
  /// rounded envelope crests (or inhale/exhale splits) can produce only dip by
  /// a few percent — a steeper threshold than HR's keeps one peak per breath.
  final double fallRatio;

  /// A confirmed peak smaller than this fraction of the recent-accepted peak
  /// amplitude is treated as a filter echo or envelope ripple, not a breath.
  /// (Absolute `minHeight` alone can not separate them once the passband is
  /// well within the signal's dynamic range.)
  final double minPeakRatio;

  /// When band-passed energy is below this fraction of total audio energy the
  /// dominant content is outside the 100-1000 Hz band (rumble, hiss, or
  /// silence) — no estimate is reported.
  final double subBandRatioThreshold;

  /// Minimum normalized autocorrelation for the [BreathPipeline.dominantPeriod]
  /// rhythm test. Below this the envelope is too noise-driven to trust.
  final double minAutocorrelation;

  /// How close the peak-derived cadence must be to an integer multiple of the
  /// autocorrelation-dominant period (0..1) — rejects envelope double-bursts
  /// and detector jitter that would otherwise halve/double the rate.
  final double cadenceHarmonicTolerance;

  /// Minimum number of full cycles a candidate dominant period must complete
  /// inside the correlation window before it can be trusted. Slow envelope
  /// drift (handling, a phone settling) only completes ~2 cycles in the 30 s
  /// window yet can out-correlate the real breath rhythm; requiring 3+ cycles
  /// rejects it while still covering down to ~6 cpm.
  final int minDominantCycles;

  /// Above this envelope periodicity the burst cadence is treated as a clean
  /// single-burst rhythm (synthetic/ideal) and not doubled to a subharmonic.
  final double singleBurstCorrFloor;

  /// Minimum relative swing between alternating short/long inter-breath
  /// intervals before they are read as an inhale/exhale pair (whose sum is the
  /// breath period) rather than detector jitter.
  final double minPairSwing;

  /// Minimum envelope energy at half the peak-train cadence, as a fraction of
  /// the cadence and half-cadence energy combined (0..1), required to accept
  /// the doubled period. A peak cadence of 30/min is ambiguous: it is either 30
  /// breaths/min with one burst per breath or 15 breaths/min with two bursts per
  /// breath. Only the presence of a genuine envelope fundamental at the
  /// half-rate (the subharmonic) can tell them apart — without it, doubling a
  /// real tachypneic rate would silently halve it.
  final double subharmonicEnergyRatio;
}

/// Real-time microphone -> RR (breaths/min) processor. Framework-free: the
/// caller pushes normalized (-1..1) PCM chunks tagged with elapsed seconds;
/// the pipeline owns its filter, envelope, peak and interval state.
///
/// Chain (VITALS_SENSING §5.2): band-pass the audio 100-1000 Hz -> short-time
/// RMS envelope (30 ms frames) -> detrend (long moving average) -> band-pass
/// the envelope 0.07-1 Hz (high-pass by low-pass subtraction, then low-pass)
/// -> peak detect (refractory + plausibility guards) -> median interval -> cpm
/// with a regularity + periodicity + SNR quality score.
class BreathPipeline {
  BreathPipeline({BreathConfig config = const BreathConfig()}) : _c = config {
    _frameLen = (_c.envelopeMs * _c.sampleRateHz / 1000).round();
    final envHz = 1000 / _c.envelopeMs;
    _detrend = MovingAverage((_c.detrendSeconds * envHz).round());
    _hp = Biquad.lowPass(
      cutoffHz: _c.cpmMin / 60,
      sampleRateHz: envHz,
    );
    // Second low-pass for a sharper high-pass cascade in [_onEnvelope] — cuts
    // sub-band tendency (slow drift) that would masquerade as a slow rhythm.
    _hp2 = Biquad.lowPass(
      cutoffHz: _c.cpmMin / 60,
      sampleRateHz: envHz,
    );
    _envLp = Biquad.lowPass(
      cutoffHz: _c.cpmMax / 60,
      sampleRateHz: envHz,
    );
    _audioBand = Biquad.bandPass(
      centerHz: _c.bandpassCenterHz,
      sampleRateHz: _c.sampleRateHz,
      q: _c.bandpassQ,
    );
    _peaks = PeakDetector(
      // Refractory ≈ hard breath ceiling (cpmMax): guards the double-peaks a
      // rounded envelope can produce at the inhale/exhale boundary.
      refractoryMs: 1000 / (_c.cpmMax / 60),
      fallRatio: _c.fallRatio,
      minHeight: 2, // just above the tiny envelope residue
    );
    _audioBandRms = Rms(_frameLen);
    _audioRawRms = Rms(_frameLen);
    _envUnitRms = Rms((3 * envHz).round());
    _envBandRms = Rms((3 * envHz).round());
    _envWindow = TimestampedWindow(capacityMs: 30000);
    _envWindowStartMs = _c.detrendSeconds * 1000;
  }

  final BreathConfig _c;

  late int _frameLen;
  late final MovingAverage _detrend;
  late final Biquad _hp;
  late final Biquad _hp2;
  late final Biquad _envLp;
  late final Biquad _audioBand;
  late final PeakDetector _peaks;
  late final Rms _audioBandRms;
  late final Rms _audioRawRms;
  late final Rms _envUnitRms;
  late final Rms _envBandRms;
  late final TimestampedWindow _envWindow;

  final List<double> _frame = [];
  double _frameStartMs = -1;

  final List<double> _ibis = [];
  double _meanPeakAmp = 0;
  int _peakCount = 0;

  double? _firstPeakTime;
  double? _lastPeakTime;
  int _usableSeconds = 0;

  double? _medianIbiMs;
  double? _lastCpm;
  bool _everHadBreath = false;

  double _lastUnit = 0;
  double _lastBand = 0;

  /// Continuous usable signal coverage so far (seconds).
  int get usableSeconds => _usableSeconds;

  double? get lastCpm => _lastCpm;

  int get ibiCount => _ibis.length;

  double? _corrAtLagMs(double lagMs) {
    final envHz = 1000 / _c.envelopeMs;
    final k = (lagMs * envHz / 1000).round();
    if (k < 1) return null;
    return _acorrAt(k);
  }

  /// Hann-windowed Goertzel power of the band-passed envelope at [freqHz].
  /// Unlike autocorrelation (which folds in every harmonic), this isolates one
  /// frequency so a true envelope fundamental can be told from leakage.
  double _envTonePower(double freqHz) {
    final vals = _envWindow.values;
    final n = vals.length;
    if (n < 8 || freqHz <= 0) return 0;
    final envHz = 1000 / _c.envelopeMs;
    final w = 2 * math.pi * freqHz / envHz;
    final coeff = 2 * math.cos(w);
    var s1 = 0.0, s2 = 0.0;
    for (var i = 0; i < n; i++) {
      final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      final s0 = vals[i] * hann + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    final p = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    return p.isFinite && p > 0 ? p : 0;
  }

  /// Envelope energy at half the peak-train cadence as a fraction of the
  /// energy at the cadence and the half-cadence combined (0..1). High when the
  /// envelope genuinely has a fundamental there (two energy bursts per breath),
  /// near zero for one burst per breath.
  double subharmonicRatio() {
    final burst = peakTrainPeriodMs();
    if (burst == null || burst <= 0) return 0;
    final fBurst = 1000 / burst;
    final pBurst = _envTonePower(fBurst);
    final pSub = _envTonePower(fBurst / 2);
    final total = pBurst + pSub;
    if (total <= 1e-12) return 0;
    return pSub / total;
  }

  /// The breath period (ms): the burst period from the peak train, doubled
  /// when the envelope shows a genuine subharmonic there.
  ///
  /// Breathing with the phone at the mouth/nose produces two energy bursts per
  /// breath (inhale + exhale), so the peak train's cadence is the *burst* rate
  /// — roughly twice the breath rate. A peak cadence is ambiguous though: the
  /// same cadence can be a slower breath with two bursts or a faster breath
  /// with one. The doubled period is accepted only when the envelope carries a
  /// real fundamental at half the cadence ([subharmonicRatio]); otherwise the
  /// cadence is taken as the breath rate, so a genuine tachypneic 30+ rate is
  /// not silently halved to 15.
  double? breathPeriodMs() {
    final burst = peakTrainPeriodMs();
    if (burst == null || burst <= 0) return null;
    final doubled = 2 * burst;
    if (doubled > 60000 / _c.cpmMin) return burst;
    // A pristine single-burst rhythm (near-perfect envelope periodicity at the
    // burst lag) is already the breath period — never double it.
    final corrBurst = _corrAtLagMs(burst);
    if (corrBurst != null && corrBurst >= _c.singleBurstCorrFloor) return burst;
    if (subharmonicRatio() >= _c.subharmonicEnergyRatio) return doubled;
    return burst;
  }

  bool get hasBreath => _everHadBreath;

  /// Ambient gate: true once the raw (unfiltered) audio RMS stays above the
  /// noise floor — the room is too loud for a reliable reading.
  bool get ambientNoisy {
    final r = _audioRawRms.value;
    return r != null && r > _c.noiseFloorRms;
  }

  /// Feeds one PCM chunk. [samples] must be normalized (-1..1);
  /// [elapsedSeconds] is the chunk's end time since session start.
  void add({required Float64List samples, required double elapsedSeconds}) {
    final n = samples.length;
    final chunkStartMs = (elapsedSeconds - n / _c.sampleRateHz) * 1000;
    for (var i = 0; i < n; i++) {
      final tMs = chunkStartMs + i / _c.sampleRateHz * 1000;

      _audioRawRms.update(samples[i]);
      final banded = _audioBand.process(samples[i]);
      _audioBandRms.update(banded);

      _frame.add(banded);
      if (_frame.length == 1) _frameStartMs = tMs;
      if (_frame.length == _frameLen) {
        final env = _audioBandRms.value ?? 0;
        _onEnvelope(env, _frameStartMs + _c.envelopeMs / 2);
        _frame.clear();
      }
    }
  }

  void _onEnvelope(double env, double timestampMs) {
    // Normalise by the local mean so gain offsets don't dominate. The detrend
    // window only reports a value once full, so until then a running mean
    // normalises too — otherwise the first few seconds of envelope oscillation
    // would be invisible and usable coverage would systematically under-read.
    final det = _detrend.update(env) ?? _runningMean(env);
    // Startup silence: env and det are both 0, so env/det would be NaN — and a
    // single NaN poisons the IIR cascade's delay line for the rest of the
    // session (NaN never leaves a recursive filter). Skip the frame instead.
    if (!det.isFinite || det <= 1e-9) return;
    final norm = env / det;
    final unit = (norm - 1) * 1000; // fractional change, in parts-per-thousand

    // Band-pass the envelope ~0.07-1 Hz: sharper high-pass (two cascaded LP
    // subtractions), then low-pass @1 Hz to kill high-frequency ripple.
    final hp1 = unit - _hp.process(unit);
    final high = hp1 - _hp2.process(hp1);
    final band = _envLp.process(high);
    _lastUnit = unit;
    _lastBand = band;
    _envUnitRms.update(unit);
    _envBandRms.update(band);
    if (timestampMs >= _envWindowStartMs && timestampMs <= _envWindowEndMs) {
      _envWindow.add(band, timestampMs: timestampMs);
    }

    final peak = _peaks.update(timestampMs: timestampMs, value: band);
    if (peak == null) return;
    final amp = peak.amplitude.abs();
    // Echo guard: the band-pass cascade leaves a low-amplitude ripple right
    // after each real crest; an absolute minHeight can't see it. Require the
    // confirmed peak to reach a meaningful fraction of recently-accepted
    // breathe amplitudes before counting it (VITALS_SENSING §5.3 robustness).
    // The reference is an EMA (not a running max) so a single startup
    // transient can't permanently reject every real breath that follows.
    _acceptedAmpFloor =
        _acceptedAmpFloor <= 0 ? amp : 0.7 * _acceptedAmpFloor + 0.3 * amp;
    if (amp < _c.minPeakRatio * _acceptedAmpFloor) return;
    _everHadBreath = true;
    _onPeak(peak);
  }

  double _acceptedAmpFloor = 0;

  int _warmCount = 0;
  double _warmMean = 0;

  /// Envelope values below [detrendSeconds] are the HP/detrend cascade's
  /// settle-in transient (a slow ramp) — including it makes the envelope's
  /// autocorrelation read as one long drift instead of the breath rhythm, so
  /// the correlation window only collects from that point on.
  double _envWindowStartMs = 0;
  double _envWindowEndMs = double.maxFinite;

  double _runningMean(double env) {
    // Seed at the first meaningful level: leading silence would otherwise drag
    // the mean toward zero, inflating the first real frame into a huge
    // transient (and, via the echo floor, rejecting every breath after it).
    if (_warmCount == 0 || (_warmMean <= 0 && env > 0)) {
      _warmMean = env;
      _warmCount = 1;
      return _warmMean;
    }
    _warmCount++;
    _warmMean += (env - _warmMean) / _warmCount;
    return _warmMean;
  }

  void _onPeak(PeakEvent peak) {
    _peakCount++;
    final amp = peak.amplitude.abs();
    _meanPeakAmp =
        _peakCount == 1 ? amp : 0.7 * _meanPeakAmp + 0.3 * amp;

    final prev = _lastPeakTime;
    _lastPeakTime = peak.timestampMs;

    if (prev == null) {
      _firstPeakTime ??= peak.timestampMs;
      return;
    }

    final gap = peak.timestampMs - prev;
    if (gap > _c.peakGapSeconds * 1000) {
      // Long dead span: the signal was lost, restart usable coverage.
    _ibis.clear();
      _firstPeakTime = peak.timestampMs;
      _usableSeconds = 0;
      return;
    }
    if (gap < 1000 / (_c.cpmMax / 60) || gap > _c.maxIbiSeconds * 1000) {
      return; // Physiologically implausible interval — a noise peak.
    }

    _ibis.add(gap);
    if (_ibis.length > 40) _ibis.removeAt(0);
    _usableSeconds = ((peak.timestampMs - _firstPeakTime!) / 1000).floor();
    _recompute();
  }

  void _recompute() {
    if (_ibis.length < 3) return;
    final sorted = [..._ibis]..sort();
    _medianIbiMs = sorted[sorted.length ~/ 2];
    _lastCpm = 60000 / _medianIbiMs!;
  }

  /// Quality in 0..1: breath regularity (dominant), rhythmic autocorrelation
  /// (separates true periodic breathing from refractory pseudo-rhythms in
  /// noise), and an envelope-SNR term. 0 until at least three breaths exist.
  double qualityScore() {
    if (_ibis.length < 3) return 0;
    return 0.6 * regularity() + 0.3 * periodicity() + 0.1 * amplitudeFactor();
  }

  /// Breath-interval regularity in 0..1 (1 - MAD/median coefficient of
  /// variation) — the dominant quality term.
  double regularity() {
    if (_ibis.length < 3) return 0;
    final median = _medianIbiMs!;
    final deviations = _ibis.map((i) => (i - median).abs()).toList()..sort();
    final mad = deviations.length.isEven
        ? (deviations[deviations.length ~/ 2 - 1] +
                deviations[deviations.length ~/ 2]) /
            2
        : deviations[deviations.length ~/ 2];
    final cv = mad / median;
    return (1 - cv).clamp(0.0, 1.0);
  }

  /// Mean confirmed-breath amplitude vs. 4x passband RMS, in 0..1 — the
  /// envelope-SNR term (small for noise, larger for clean breath bursts).
  double amplitudeFactor() {
    final r = _audioBandRms.value;
    return r != null && r > 1e-9
        ? (_meanPeakAmp / (4 * r)).clamp(0.0, 1.0)
        : 0.0;
  }

  /// Normalized autocorrelation of the band-passed envelope at the dominant
  /// breath period. ≈1 for true periodic breathing; ≈0 for noise.
  double periodicity() => dominantPeriod()?.corr ?? 0;

  /// Normalized autocorrelation of the envelope at the peak-derived cadence
  /// (the median inter-breath interval). High when the detected peaks sit on a
  /// real envelope period; low when they are filter echoes.
  double? cadenceCorrelation() {
    final m = _medianIbiMs;
    if (m == null) return null;
    final envHz = 1000 / _c.envelopeMs;
    final k = (m * envHz / 1000).round();
    if (k < 1) return null;
    return _acorrAt(k);
  }

  /// The fundamental breath period (ms) inferred from the peak train alone.
  ///
  /// The envelope autocorrelation is easily captured by slow drift, but the
  /// detected peaks carry no drift. A real breath yields either one crest per
  /// cycle (regular intervals) or a repeated short/long pair (a crest plus a
  /// filter echo, e.g. [1080, 6390, 1170, 6600, ...] whose pair sums to the
  /// breath period). The median interval is robust to a lone echo; only when
  /// the intervals genuinely alternate does it fall to the echo's half-period,
  /// and there the pair sum (2× mean) recovers the true period.
  double? peakTrainPeriodMs() {
    final n = _ibis.length;
    if (n == 0) return null;
    final sorted = [..._ibis]..sort();
    final median = sorted[n ~/ 2];
    if (n < 6) return median;
    final alternating = _ibiAcorrAt(1) < -0.3 && _ibiAcorrAt(2) >= 0.5;
    if (alternating) {
      // Require a substantial short/long swing: a couple of percent of detector
      // jitter also alternates, and treating it as the inhale/exhale pair would
      // halve a genuine tachypneic rate (35 -> ~18, 45 -> ~22).
      var meanEven = 0.0, meanOdd = 0.0;
      var ne = 0, no = 0;
      for (var i = 0; i < n; i++) {
        if (i.isEven) {
          meanEven += _ibis[i];
          ne++;
        } else {
          meanOdd += _ibis[i];
          no++;
        }
      }
      meanEven /= ne;
      meanOdd /= no;
      final mean = (meanEven + meanOdd) / 2;
      final swing = (meanEven - meanOdd).abs() / mean;
      if (swing >= _c.minPairSwing) return 2 * mean;
    }
    return median;
  }

  double _ibiAcorrAt(int lag) {
    final n = _ibis.length;
    final m = n - lag;
    if (m <= 1) return 0;
    var ma = 0.0, mb = 0.0;
    for (var i = 0; i < m; i++) {
      ma += _ibis[i];
      mb += _ibis[i + lag];
    }
    ma /= m;
    mb /= m;
    var xy = 0.0, xx = 0.0, yy = 0.0;
    for (var i = 0; i < m; i++) {
      final a = _ibis[i] - ma;
      final b = _ibis[i + lag] - mb;
      xy += a * b;
      xx += a * a;
      yy += b * b;
    }
    if (xx == 0 || yy == 0) return 0;
    final r = xy / math.sqrt(xx * yy);
    return r < -1 ? -1.0 : (r > 1 ? 1.0 : r);
  }

  /// The lag (ms) and correlation of the strongest autocorrelation peak over
  /// plausible breath periods (cpmMin-cpmMax). Null when too noise-driven.
  ({double lagMs, double corr})? dominantPeriod() {
    final vals = _envWindow.values;
    if (vals.length < 6) return null;
    final envHz = 1000 / _c.envelopeMs;
    final minKs = (60 / _c.cpmMax * envHz).round(); // == 1 s period
    var maxKs = (60 / _c.cpmMin * envHz).round(); // == 15 s period
    // A session shorter than the slowest period shouldn't stop us measuring
    // faster rhythms: clamp the search to lags the window can actually hold.
    if (maxKs >= vals.length) maxKs = vals.length - 1;
    // Reject slow drift: a candidate period must complete at least
    // [minDominantCycles] cycles in the window. A 14 s wander over a 30 s
    // window only manages ~2 and can out-correlate the real breath rhythm.
    final cycleCap = vals.length ~/ _c.minDominantCycles;
    if (maxKs > cycleCap) maxKs = cycleCap;
    if (maxKs <= minKs) return null;

    // Global best correlation and lag.
    var best = 0.0, bestLag = 0.0;
    for (var k = minKs; k <= maxKs; k++) {
      final c = _acorrAt(k);
      if (c > best) {
        best = c;
        bestLag = k * 1000 / envHz;
      }
    }
    if (best < _c.minAutocorrelation) return null;

    // Among periods whose correlation is essentially as strong as the global
    // peak, prefer the shortest — the physiologically first harmonic.
    var lagMs = 0.0;
    for (var k = minKs; k <= maxKs; k++) {
      if (_acorrAt(k) >= 0.95 * best) {
        lagMs = k * 1000 / envHz;
        break;
      }
    }
    return (lagMs: lagMs > 0 ? lagMs : bestLag, corr: best);
  }

  double _acorrAt(int lagK) {
    final vals = _envWindow.values;
    if (lagK >= vals.length) return 0;
    final n = vals.length - lagK;
    var meanA = 0.0, meanB = 0.0;
    for (var i = 0; i < n; i++) {
      meanA += vals[i];
      meanB += vals[i + lagK];
    }
    meanA /= n;
    meanB /= n;
    var xy = 0.0, xx = 0.0, yy = 0.0;
    for (var i = 0; i < n; i++) {
      final a = vals[i] - meanA;
      final b = vals[i + lagK] - meanB;
      xy += a * b;
      xx += a * a;
      yy += b * b;
    }
    if (xx == 0 || yy == 0) return 0;
    final r = xy / math.sqrt(xx * yy);
    return r < 0 ? 0.0 : (r > 1 ? 1.0 : r);
  }

  /// Dominant audio energy sits outside the 100-1000 Hz band (rumble/hiss/
  /// silence) — no estimate should be trusted.
  bool get subBandDominant {
    final u = _audioRawRms.value;
    final b = _audioBandRms.value;
    if (u == null || b == null) return false;
    return b / (u + 1e-9) < _c.subBandRatioThreshold;
  }

  /// The envelope's dominant variation sits below 0.07 Hz — the breathing band
  /// edge — so the slow ripple that survives peak detection is a drift/rumble
  /// artifact, not a rate (a 3 bpm signal reads as a fast cadence otherwise;
  /// mirrors HR's 30-bpm sub-band guard).
  bool get envelopeSubBandDominant {
    final u = _envUnitRms.value;
    final b = _envBandRms.value;
    if (u == null || b == null) return false;
    return b / (u + 1e-9) < _c.subBandRatioThreshold;
  }

  ReadingConfidence confidence() {
    if (_ibis.length < 3 || _usableSeconds < _c.minUsableSeconds) {
      return ReadingConfidence.low;
    }
    final q = qualityScore();
    if (q >= _c.qualityHigh) return ReadingConfidence.high;
    if (q >= _c.qualityMedium) return ReadingConfidence.medium;
    return ReadingConfidence.low;
  }

  /// Live diagnostics snapshot for the debug panel (label -> value). Mirrors
  /// PpgPipeline.debugSnapshot so the supervised log tool (VITALS_SENSING
  /// §4.2) can separate clean from face-obscured/ambient sessions.
  Map<String, String> debugSnapshot() {
    final dom = dominantPeriod();
    return {
      'breath': _everHadBreath ? 'yes' : 'no',
      'peaks': '$_peakCount',
      'ibis': '${_ibis.length}',
      'usable': '${_usableSeconds}s',
      'cpm': _lastCpm?.toStringAsFixed(1) ?? '—',
      'ibi_ms': _medianIbiMs?.toStringAsFixed(0) ?? '—',
      'peak_amp': _meanPeakAmp.toStringAsFixed(2),
      'band_rms': (_audioBandRms.value ?? 0).toStringAsFixed(3),
      'raw': (_audioRawRms.value ?? 0).toStringAsFixed(4),
      'envunit': _lastUnit.toStringAsFixed(1),
      'envband': _lastBand.toStringAsFixed(1),
      'lag_ms': dom?.lagMs.toStringAsFixed(0) ?? '—',
      'corr': dom?.corr.toStringAsFixed(2) ?? '—',
      'cad_corr': cadenceCorrelation()?.toStringAsFixed(2) ?? '—',
      'sub_e': subharmonicRatio().toStringAsFixed(2),
      'reg': regularity().toStringAsFixed(2),
      'amp': amplitudeFactor().toStringAsFixed(2),
      'noisy': ambientNoisy ? 'yes' : 'no',
      'sub_band': subBandDominant ? 'yes' : 'no',
      'env_sub': envelopeSubBandDominant ? 'yes' : 'no',
      'quality': qualityScore().toStringAsFixed(2),
    };
  }

  /// Current estimate; null before enough breaths exist — or when the room is
  /// noisy, the signal is out of band, or no stable peak rhythm was found.
  BreathEstimate? estimate() {
    if (ambientNoisy || subBandDominant || envelopeSubBandDominant) return null;
    if (_ibis.length < 3) return null;

    // Rate comes from the peak train (drift-free); the envelope's periodicity
    // is folded in via [confidence] rather than overriding the measured rate.
    final periodMs = breathPeriodMs();
    if (periodMs == null || periodMs <= 0) return null;
    final cpm = 60000 / periodMs;

    var conf = confidence();
    String? note;
    if (cpm < _c.cpmMin || cpm > _c.cpmMax) {
      conf = ReadingConfidence.low;
      note = 'Rate outside the screening band '
          '(${_c.cpmMin.round()}-${_c.cpmMax.round()} breaths/min).';
    }
    return BreathEstimate(
      cpm: cpm,
      confidence: conf,
      usableSeconds: _usableSeconds,
      note: note,
    );
  }

  /// Early finish is safe when quality is acceptable, enough usable coverage
  /// has passed the early bar, and a rhythm-sanitised estimate exists.
  bool earlyFinishEligible() {
    return estimate() != null &&
        _usableSeconds >= _c.earlyFinishUsableSeconds &&
        confidence() != ReadingConfidence.low;
  }

  void reset() {
    _frame.clear();
    _detrend.clear();
    _warmCount = 0;
    _warmMean = 0;
    _envWindowStartMs = _c.detrendSeconds * 1000;
    _envWindowEndMs = double.maxFinite;
    _hp.reset();
    _hp2.reset();
    _envLp.reset();
    _audioBand.reset();
    _peaks.reset();
    _audioBandRms.clear();
    _audioRawRms.clear();
    _envUnitRms.clear();
    _envBandRms.clear();
    _envWindow.clear();
    _ibis.clear();
    _meanPeakAmp = 0;
    _peakCount = 0;
    _acceptedAmpFloor = 0;
    _firstPeakTime = null;
    _lastPeakTime = null;
    _usableSeconds = 0;
    _medianIbiMs = null;
    _lastCpm = null;
    _everHadBreath = false;
  }
}
import 'dart:math' as math;

import '../dsp/biquad.dart';
import '../dsp/movavg.dart';
import '../dsp/peak_detect.dart';
import '../dsp/rms.dart';
import '../dsp/window.dart';
import '../models.dart';

/// One live/final PPG estimate.
class PpgEstimate {
  const PpgEstimate({
    required this.bpm,
    required this.confidence,
    this.usableSeconds = 0,
    this.note,
  });

  final double bpm;
  final ReadingConfidence confidence;
  final int usableSeconds;
  final String? note;
}

/// Tunable HR filtering/quality constants (VITALS_SENSING §4.2/§9.3 — any
/// change is a DECISIONS entry).
class PpgConfig {
  const PpgConfig({
    this.sampleRateHz = 30,
    this.bpmMin = 42,
    this.bpmMax = 210,
    this.detrendSeconds = 2,
    this.minUsableSeconds = 14,
    this.earlyFinishUsableSeconds = 12,
    this.maxIbiSeconds = 1.8,
    this.peakGapSeconds = 4,
    this.qualityHigh = 0.75,
    this.qualityMedium = 0.50,
    this.maxAcceptableDriftBpm = 4.0,
    this.subBandRatioThreshold = 0.25,
    this.minAutocorrelation = 0.5,
    this.cadenceHarmonicTolerance = 0.3,
  });

  /// Frames per second.
  final double sampleRateHz;

  /// Valid HR range (band edges, bpm).
  final double bpmMin;
  final double bpmMax;

  /// Detrend moving-average length (seconds).
  final double detrendSeconds;

  /// Seconds of continuous usable signal required before [estimate] can
  /// report anything but low confidence.
  final int minUsableSeconds;

  /// The service may finish early once this many usable seconds exist.
  final int earlyFinishUsableSeconds;

  /// Max accepted inter-beat interval (seconds) — the low-bpm guard.
  final double maxIbiSeconds;

  /// A peak gap longer than this (seconds) resets "usable coverage" — the
  /// signal was lost, not just slow.
  final double peakGapSeconds;

  /// Quality-score thresholds for high/medium confidence. The medium cutoff
  /// (0.50) is calibrated from on-device labeled data + follow-up (DECISIONS
  /// 2026-09-12d/e): clean final-second quality ranged 0.55-0.56 with drift
  /// 0.3-2.6 bpm and never dropped below 0.50 during a proper reading, while
  /// chaotic spikes topped at 0.48 before falling — see bpmDrift.
  final double qualityHigh;
  final double qualityMedium;

  /// A reading is never confident while its per-beat BPM estimate is still
  /// wandering more than this (bpm) over the recent window. A real pulse
  /// converges (final drift 0.3-2.6 in calibration); a chaotic signal keeps
  /// jumping (4.8-9.2). Encodes "the estimate must have settled".
  final double maxAcceptableDriftBpm;

  /// When band-passed energy is below this fraction of total signal energy,
  /// the dominant rhythm is sub-band (e.g. a 30 bpm bradycardia mimicking a
  /// fast pulse via filter ringing) — no estimate is reported.
  final double subBandRatioThreshold;

  /// Minimum normalized autocorrelation for the [PpgPipeline.dominantPeriod]
  /// rhythm test. Below this the signal is too noise-driven to trust.
  final double minAutocorrelation;

  /// How close the peak-derived cadence must be to an integer multiple of the
  /// autocorrelation-dominant period (0..1). A dicrotic notch or filter
  /// ringing peaks N per true beat → the cadence is a multiple of the true
  /// period; a value like 0.15 (≈ 30 bpm read as 200) is not.
  final double cadenceHarmonicTolerance;
}

/// Real-time PPG->BPM processor. Framework-free: the caller pushes mean-red
/// frame values with millisecond timestamps; the pipeline owns its filter,
/// peak and IBI state and reports a running [estimate].
///
/// Chain (VITALS_SENSING §4.2): normalize -> detrend (long moving average) ->
/// band-pass 0.7-3.5 Hz (high-pass by low-pass subtraction, then low-pass) ->
/// peak detect (refractory + plausibility guards) -> median IBI -> BPM with a
/// regularity + SNR quality score.
class PpgPipeline {
  PpgPipeline({PpgConfig config = const PpgConfig()}) : _c = config {
    _detrend = MovingAverage((config.detrendSeconds * config.sampleRateHz).round());
    _highPass = Biquad.lowPass(
      cutoffHz: 0.7,
      sampleRateHz: config.sampleRateHz,
    );
    // Second low-pass for a sharper high-pass cascade in [add] — cuts
    // sub-band leakage (e.g. a 30 bpm sinusoid) that would otherwise masquerade
    // as a fast pseudo-rhythm.
    _highPass2 = Biquad.lowPass(
      cutoffHz: 0.7,
      sampleRateHz: config.sampleRateHz,
    );
    _bandLp = Biquad.lowPass(
      cutoffHz: 3.5,
      sampleRateHz: config.sampleRateHz,
    );
    _peaks = PeakDetector(
      // Refractory ≈ hard beat ceiling (240 bpm): guards double-peaks and
      // dicrotic notches; the tuned band edge is bpmMax.
      refractoryMs: 1000 / 4,
      fallRatio: 0.25,
      minHeight: 2, // just above the tiny high-frequency residue
    );
    _rms = Rms((3 * config.sampleRateHz).round());
    _unitRms = Rms((3 * config.sampleRateHz).round());
    _bandWindow = TimestampedWindow(capacityMs: 6000);
  }

  final PpgConfig _c;
  late final MovingAverage _detrend;
  late final Biquad _highPass;
  late final Biquad _highPass2;
  late final Biquad _bandLp;
  late final PeakDetector _peaks;
  late final Rms _rms;
  late final Rms _unitRms;
  late final TimestampedWindow _bandWindow;

  final List<double> _ibis = [];
  final List<double> _recentBpm = [];
  double _meanPeakAmp = 0;
  int _peakCount = 0;

  double? _firstPeakTime;
  double? _lastPeakTime;
  int _usableSeconds = 0;

  double? _medianIbiMs;
  double? _lastBpm;
  bool _everHadBeat = false;

  /// Continuous usable signal coverage so far (seconds).
  int get usableSeconds => _usableSeconds;

  double? get lastBpm => _lastBpm;

  bool get hasBeat => _everHadBeat;

  /// Mean amplitude of the accepted band-pass peaks (parts-per-thousand).
  double get meanPeakAmp => _meanPeakAmp;

  /// RMS of the band-passed signal at the sample rate, in ppt units.
  double? get bandRms => _rms.value;

  /// Estimate stability bpm — range (max−min) of the last ~15 per-beat BPM
  /// updates. A real pulse converges and holds (small drift); noise-driven
  /// pseudo-peaks wander. Feeds the log-based confidence calibration.
  double? get bpmDrift {
    if (_recentBpm.length < 3) return null;
    var min = double.infinity, max = double.negativeInfinity;
    for (final v in _recentBpm) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return max - min;
  }

  /// Live diagnostics snapshot for the debug panel (label -> value).
  Map<String, String> debugSnapshot() {
    final dom = dominantPeriod();
    return {
      'beat': _everHadBeat ? 'yes' : 'no',
      'peaks': '$_peakCount',
      'usable': '${_usableSeconds}s',
      'bpm': _lastBpm?.toStringAsFixed(0) ?? '—',
      'ibi_ms': _medianIbiMs?.toStringAsFixed(0) ?? '—',
      'peak_amp': _meanPeakAmp.toStringAsFixed(2),
      'band_rms': (_rms.value ?? 0).toStringAsFixed(3),
      'energy': (_unitRms.value ?? 0).toStringAsFixed(1),
      'period_ms': dom?.lagMs.toStringAsFixed(0) ?? '—',
      'corr': dom?.corr.toStringAsFixed(2) ?? '—',
      'reg': regularityScore().toStringAsFixed(2),
      'amp': ampFactor().toStringAsFixed(2),
      'drift': bpmDrift?.toStringAsFixed(1) ?? '—',
      'sub_band': subBandDominant ? 'yes' : 'no',
      'quality': qualityScore().toStringAsFixed(2),
    };
  }

  /// Feeds one mean-red frame at [timestampMs] (ms since session start).
  void add({required double timestampMs, required double redMean}) {
    // Normalise by the local mean so brightness offsets/drift don't dominate.
    final norm = redMean / (_detrend.update(redMean) ?? redMean);
    final unit = (norm - 1) * 1000; // fractional change, in parts-per-thousand

    // Band-pass ~0.7-3.5 Hz: sharper high-pass (two cascaded LP subtractions),
    // then low-pass @3.5 Hz to kill high-frequency residue.
    final hp1 = unit - _highPass.process(unit);
    final high = hp1 - _highPass2.process(hp1);
    final band = _bandLp.process(high);
    _rms.update(band);
    _unitRms.update(unit);
    _bandWindow.add(band, timestampMs: timestampMs);

    final peak = _peaks.update(timestampMs: timestampMs, value: band);
    if (peak == null) return;
    _everHadBeat = true;
    _onPeak(peak);
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
    if (gap < 1000 / _c.bpmMax || gap > _c.maxIbiSeconds * 1000) {
      return; // physiologically implausible interval — a noise peak.
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
    _lastBpm = 60000 / _medianIbiMs!;
    _recentBpm.add(_lastBpm!);
    if (_recentBpm.length > 15) _recentBpm.removeAt(0);
  }

  /// Quality in 0..1: peak SNR (bumped from 0.1 → 0.2 so strong distinct beats
  /// matter more), beat regularity, and rhythmic autocorrelation (separates
  /// true periodic HR from refractory-induced pseudo-rhythms in noise). 0 until
  /// at least three beats exist.
  final double _regWeight = 0.5;
  final double _corrWeight = 0.3;
  final double _ampWeight = 0.2;

  double qualityScore() {
    if (_ibis.length < 3) return 0;
    return _regWeight * regularityScore() +
        _corrWeight * periodicity() +
        _ampWeight * ampFactor();
  }

  /// Beat regularity 0..1 from a TRAILING IBI window (last [qualityWindow]).
  /// Using only recent beats means a momentarily missed/garbled beat at the
  /// start (finger placement, torch settling) stops dragging the quality of an
  /// otherwise steady signal for the rest of the session — the same reason the
  /// estimate error shrinks as the session progresses.
  double regularityScore() {
    const window = 12;
    final recent =
        _ibis.length > window ? _ibis.sublist(_ibis.length - window) : _ibis;
    if (recent.length < 3) return 0;
    final sorted = [...recent]..sort();
    final median = sorted[sorted.length ~/ 2];
    final deviations = recent
        .map((i) => (i - median).abs())
        .toList()
      ..sort();
    final mad = deviations.length.isEven
        ? (deviations[deviations.length ~/ 2 - 1] +
                deviations[deviations.length ~/ 2]) /
            2
        : deviations[deviations.length ~/ 2];
    final cv = mad / median;
    return (1 - cv).clamp(0.0, 1.0);
  }

  /// Peak-versus-background term 0..1: strong distinct peaks relative to the
  /// band RMS (a clean pulse rhythm) score high.
  double ampFactor() {
    final r = _rms.value;
    return r != null && r > 1e-9
        ? (_meanPeakAmp / (4 * r)).clamp(0.0, 1.0)
        : 0.0;
  }

  /// Normalized autocorrelation of the band-passed signal at the dominant
  /// rhythm period. ≈1 for a true periodic pulse; ≈0 for noise-driven
  /// pseudo-peaks.
  double periodicity() => dominantPeriod()?.corr ?? 0;

  /// The lag (ms) and correlation of the strongest autocorrelation peak over
  /// plausible rhythm periods (15-210 bpm). Null when the signal is too
  /// noise-driven for any period to dominate.
  ({double lagMs, double corr})? dominantPeriod() {
    final vals = _bandWindow.values;
    if (vals.length < 6) return null;
    final minKs = (0.286 * _c.sampleRateHz).round(); // ≥ 210 bpm
    final maxKs = (4.0 * _c.sampleRateHz).round(); // ≤ 15 bpm
    if (maxKs <= minKs || maxKs >= vals.length) return null;

    // Global best correlation and lag.
    var best = 0.0, bestLag = 0.0;
    for (var k = minKs; k <= maxKs; k++) {
      final c = _acorrAt(k);
      if (c > best) {
        best = c;
        bestLag = k * 1000 / _c.sampleRateHz;
      }
    }
    if (best < _c.minAutocorrelation) return null;

    // Among periods whose correlation is essentially as strong as the global
    // peak (window-trend artifacts can correlate perfectly at large lags),
    // prefer the shortest — the physiologically first harmonic.
    var lagMs = 0.0;
    for (var k = minKs; k <= maxKs; k++) {
      if (_acorrAt(k) >= 0.95 * best) {
        lagMs = k * 1000 / _c.sampleRateHz;
        break;
      }
    }
    return (lagMs: lagMs > 0 ? lagMs : bestLag, corr: best);
  }

  double _acorrAt(int lagK) {
    final vals = _bandWindow.values;
    if (lagK >= vals.length) return 0;
    var xy = 0.0, xx = 0.0, yy = 0.0;
    for (var i = 0; i + lagK < vals.length; i++) {
      xy += vals[i] * vals[i + lagK];
      xx += vals[i] * vals[i];
      yy += vals[i + lagK] * vals[i + lagK];
    }
    if (xx == 0 || yy == 0) return 0;
    final r = xy / math.sqrt(xx * yy);
    return r < 0 ? 0.0 : (r > 1 ? 1.0 : r);
  }

  /// Dominant energy sits below the 0.7-3.5 Hz band (e.g. a 30 bpm bradycardia
  /// whose filter ringing fakes a fast pulse). No estimate should be trusted.
  bool get subBandDominant {
    final u = _unitRms.value;
    final b = _rms.value;
    if (u == null || b == null) return false;
    return b / (u + 1e-9) < _c.subBandRatioThreshold;
  }

  ReadingConfidence confidence() {
    if (_ibis.length < 3 ||
        _usableSeconds < _c.minUsableSeconds ||
        (bpmDrift ?? double.infinity) > _c.maxAcceptableDriftBpm) {
      return ReadingConfidence.low;
    }
    final q = qualityScore();
    if (q >= _c.qualityHigh) return ReadingConfidence.high;
    if (q >= _c.qualityMedium) return ReadingConfidence.medium;
    return ReadingConfidence.low;
  }

  /// Current estimate; null before enough beats exist — or when the signal's
  /// true rhythm can't be trusted (sub-band energy, noise-driven, or a peak
  /// cadence that isn't a harmonic of the dominant period).
  PpgEstimate? estimate() {
    if (subBandDominant) return null;
    final bpm = _lastBpm;
    if (bpm == null) return null;

    // Rhythm sanity: the peak-derived cadence must sit near an integer
    // multiple of the autocorrelation-dominant period. This rejects filter
    // ringing (30 bpm read as 200) and dicrotic double-counts.
    final dominant = dominantPeriod();
    if (dominant == null) {
      // Band autocorrelation is too weak to confirm a rhythm period. That is
      // NOT proof of noise — a genuinely beating fingertip can score poorly
      // here on some devices (calibrated with labeled data: clean signals have
      // null corr yet are accurate). The peak train itself is strong rhythm
      // evidence, so fall back to it only when the beats are very regular,
      // the confidence-score is at least medium, AND the estimate has settled
      // (drift <= max — final drift was 0.3-2.6 clean vs 4.8-9.2 chaotic).
      if (regularityScore() < 0.7 ||
          qualityScore() < _c.qualityMedium ||
          (bpmDrift ?? double.infinity) > _c.maxAcceptableDriftBpm) {
        return null;
      }
    } else {
      final k = _medianIbiMs! / dominant.lagMs;
      final harmonics = k.round();
      if (harmonics < 1 || (k - harmonics).abs() > _c.cadenceHarmonicTolerance) {
        return null;
      }
    }

    var conf = confidence();
    String? note;
    if (bpm < _c.bpmMin || bpm > _c.bpmMax) {
      conf = ReadingConfidence.low;
      note = 'Rate outside the screening band '
          '(${_c.bpmMin.round()}-${_c.bpmMax.round()} bpm).';
    }
    return PpgEstimate(
      bpm: bpm,
      confidence: conf,
      usableSeconds: _usableSeconds,
      note: note,
    );
  }

/// Early finish is safe only when quality is already HIGH and usable
  /// coverage exceeds the early bar with a rhythm-sanitised estimate. Anything
  /// that is merely "medium" keeps measuring — the estimate keeps converging
  /// (error drops with time) and the full window is worth taking.
  bool earlyFinishEligible() {
    return estimate() != null &&
        _usableSeconds >= _c.earlyFinishUsableSeconds &&
        confidence() == ReadingConfidence.high;
  }

  void reset() {
    _detrend.clear();
    _highPass.reset();
    _highPass2.reset();
    _bandLp.reset();
    _peaks.reset();
    _rms.clear();
    _unitRms.clear();
    _bandWindow.clear();
    _ibis.clear();
    _recentBpm.clear();
    _meanPeakAmp = 0;
    _peakCount = 0;
    _firstPeakTime = null;
    _lastPeakTime = null;
    _usableSeconds = 0;
    _medianIbiMs = null;
    _lastBpm = null;
    _everHadBeat = false;
  }
}
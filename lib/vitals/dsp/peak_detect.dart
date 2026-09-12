// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// A detected peak: where it occurred and how tall it was.
class PeakEvent {
  const PeakEvent({required this.timestampMs, required this.amplitude});

  final double timestampMs;
  final double amplitude;

  @override
  String toString() => 'PeakEvent(${timestampMs.toStringAsFixed(1)}ms, '
      '${amplitude.toStringAsFixed(3)})';
}

/// Peak detector with a refractory window that confirms a peak only after the
/// signal has fallen [fallRatio] below its running maximum.
///
/// Stateful: feed samples in time order via [update]; a completed peak is
/// returned exactly when it is confirmed (falling edge past [fallRatio]), so
/// inter-peak intervals fall out naturally from returned timestamps.
class PeakDetector {
  PeakDetector({
    required this.refractoryMs,
    this.fallRatio = 0.25,
    this.minHeight = 0,
  });

  /// Minimum gap between accepted peaks (milliseconds). Suppresses the double
  /// peaks that appear at the start of a beat (dicrotic notch) and enforces
  /// the hard physiological ceiling (e.g. 240 ms ≈ 250 bpm).
  final double refractoryMs;

  /// Fraction of the candidate peak the signal must fall below it to confirm
  /// completion (0.25 = a quarter).
  final double fallRatio;

  /// Absolute minimum peak amplitude to accept.
  final double minHeight;

  double? _peakTime;
  double? _peakValue;
  double? _lastAcceptedTime;
  int _acceptedCount = 0;

  /// Peaks accepted so far.
  int get acceptedCount => _acceptedCount;

  /// Feeds one sample; may return a freshly confirmed [PeakEvent].
  PeakEvent? update({required double timestampMs, required double value}) {
    final done = _peakValue != null && value <= _peakValue! * (1 - fallRatio);
    if (done) {
      final peak = PeakEvent(
        timestampMs: _peakTime!,
        amplitude: _peakValue!,
      );
      _peakTime = null;
      _peakValue = null;
      final fresh = _lastAcceptedTime == null ||
          peak.timestampMs - _lastAcceptedTime! >= refractoryMs;
      if (fresh && peak.amplitude >= minHeight) {
        _lastAcceptedTime = peak.timestampMs;
        _acceptedCount++;
        return peak;
      }
      return null;
    }
    // Rising or plateau: refresh the candidate maximum.
    if (_peakValue == null || value >= _peakValue!) {
      _peakTime = timestampMs;
      _peakValue = value;
    }
    return null;
  }

  void reset() {
    _peakTime = null;
    _peakValue = null;
    _lastAcceptedTime = null;
    _acceptedCount = 0;
  }
}
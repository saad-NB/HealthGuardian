import 'dart:math' as math;

/// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// Root-mean-square energy over a sliding window of [window] samples.
///
/// Mirrors [MovingAverage]'s "null until full window" contract so callers can
/// distinguish "not enough data" from a genuinely silent/smooth signal.
class Rms {
  Rms(this.window);

  /// Number of samples in the RMS window.
  final int window;

  final List<double> _samples = [];
  double _sumSquares = 0;

  double? _value;

  /// Pushes [x]; returns the RMS once the window is full.
  double? update(double x) {
    _samples.add(x);
    _sumSquares += x * x;
    if (_samples.length > window) {
      final dropped = _samples.removeAt(0);
      _sumSquares -= dropped * dropped;
    }
    if (_samples.length >= window) {
      _value = math.sqrt(_sumSquares / _samples.length);
      return _value;
    }
    return null;
  }

  /// Latest RMS, or null if the window isn't full yet.
  double? get value => _value;

  void clear() {
    _samples.clear();
    _sumSquares = 0;
    _value = null;
  }
}
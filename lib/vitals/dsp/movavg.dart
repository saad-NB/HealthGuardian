// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// Sliding-window arithmetic mean. Returns null until a full [window] of
/// samples has been seen, so a caller can tell "not enough data yet" apart
/// from a real (possibly flat) average.
class MovingAverage {
  MovingAverage(this.window);

  /// Number of samples in the averaging window.
  final int window;

  final List<double> _samples = [];
  double _sum = 0;

  double? _value;

  /// Pushes [x]; returns the current average once the window is full.
  double? update(double x) {
    _samples.add(x);
    _sum += x;
    if (_samples.length > window) {
      _sum -= _samples.removeAt(0);
    }
    if (_samples.length >= window) {
      _value = _sum / _samples.length;
      return _value;
    }
    return null;
  }

  /// Latest full-window average, or null if the window isn't full yet.
  double? get value => _value;

  void clear() {
    _samples.clear();
    _sum = 0;
    _value = null;
  }
}
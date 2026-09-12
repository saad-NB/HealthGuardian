// Pure-Dart signal-window helpers (no Flutter/plugin deps, headless-testable).

/// Sliding window of timestamped samples. Older entries are dropped once they
/// fall outside [capacityMs], so callers always see a bounded, time-ordered
/// view of the most recent signal.
class TimestampedWindow {
  TimestampedWindow({required this.capacityMs});

  /// Keep at most this many milliseconds of history.
  final double capacityMs;

  final List<double> _values = [];
  final List<double> _times = [];

  int get length => _values.length;
  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;

  /// Time-sorted samples (oldest first).
  List<double> get values => _values;
  List<double> get times => _times;

  double get newestValue => _values.last;
  double get newestTime => _times.last;

  /// Appends a sample, discarding entries older than `timestampMs - capacityMs`.
  void add(double value, {required double timestampMs}) {
    if (_values.isNotEmpty && timestampMs < _times.last) {
      throw ArgumentError(
        'Samples must arrive in non-decreasing order '
        '($timestampMs < ${_times.last}).',
      );
    }
    _values.add(value);
    _times.add(timestampMs);
    final cutoff = timestampMs - capacityMs;
    while (_values.isNotEmpty && _times.first < cutoff) {
      _values.removeAt(0);
      _times.removeAt(0);
    }
  }

  /// Number of samples at or after [timestampMs].
  int countSince(double timestampMs) {
    var count = 0;
    for (var i = _times.length - 1; i >= 0; i--) {
      if (_times[i] < timestampMs) break;
      count++;
    }
    return count;
  }

  void clear() {
    _values.clear();
    _times.clear();
  }
}
import 'dart:math' as math;

/// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// Second-order IIR filter (RBJ Audio Cookbook coefficients, Direct Form II
/// transposed). Numerically stable enough for the low sample rates used here
/// (audio-grade precision; float64 arithmetic throughout).
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  factory Biquad.lowPass({
    required double cutoffHz,
    required double sampleRateHz,
    double q = 0.7071067811865476,
  }) {
    final w0 = 2 * math.pi * cutoffHz / sampleRateHz;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    // RBJ coefficients (a0 normalized to 1).
    return Biquad._(
      (1 - cosW0) / 2 / (1 + alpha),
      (1 - cosW0) / (1 + alpha),
      (1 - cosW0) / 2 / (1 + alpha),
      -2 * cosW0 / (1 + alpha),
      (1 - alpha) / (1 + alpha),
    );
  }

  factory Biquad.bandPass({
    required double centerHz,
    required double sampleRateHz,
    required double q,
  }) {
    final w0 = 2 * math.pi * centerHz / sampleRateHz;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2 * q);
    // Constant-skirt-gain band-pass (RBJ).
    return Biquad._(
      alpha / (1 + alpha),
      0,
      -alpha / (1 + alpha),
      -2 * cosW0 / (1 + alpha),
      (1 - alpha) / (1 + alpha),
    );
  }

  final double _b0, _b1, _b2, _a1, _a2;

  // DF2T delay-line states.
  double _s1 = 0, _s2 = 0;

  /// Filters one sample.
  double process(double x) {
    // Defensive: a single non-finite input (or a numerically poisoned state)
    // would otherwise propagate NaN through the recursive delay line forever.
    if (!x.isFinite) x = 0;
    final y = _b0 * x + _s1;
    _s1 = _b1 * x - _a1 * y + _s2;
    _s2 = _b2 * x - _a2 * y;
    if (!y.isFinite || !_s1.isFinite || !_s2.isFinite) {
      reset();
      return 0;
    }
    return y;
  }

  /// Resets filter state (call when starting a fresh segment).
  void reset() {
    _s1 = 0;
    _s2 = 0;
  }
}
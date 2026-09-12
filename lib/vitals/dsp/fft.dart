import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// In-place iterative radix-2 Cooley-Tukey FFT.
///
/// [re] and [im] must share the same power-of-two length. The forward transform
/// is unscaled; [inverse] applies the `1/N` normalization so a forward followed
/// by an inverse is the identity (within rounding).
void fft(Float64List re, Float64List im, {bool inverse = false}) {
  final n = re.length;
  if (n <= 1) return;
  assert(im.length == n, 're/im length mismatch');
  assert((n & (n - 1)) == 0, 'fft length must be a power of two');

  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  // Butterflies.
  for (var len = 2; len <= n; len <<= 1) {
    final ang = (inverse ? 2 : -2) * math.pi / len;
    final wRe = math.cos(ang);
    final wIm = math.sin(ang);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var curRe = 1.0, curIm = 0.0;
      for (var k = 0; k < half; k++) {
        final j = i + k + half;
        final vRe = re[j] * curRe - im[j] * curIm;
        final vIm = re[j] * curIm + im[j] * curRe;
        re[j] = re[i + k] - vRe;
        im[j] = im[i + k] - vIm;
        re[i + k] += vRe;
        im[i + k] += vIm;
        final nextRe = curRe * wRe - curIm * wIm;
        curIm = curRe * wIm + curIm * wRe;
        curRe = nextRe;
      }
    }
  }

  if (inverse) {
    final inv = 1.0 / n;
    for (var i = 0; i < n; i++) {
      re[i] *= inv;
      im[i] *= inv;
    }
  }
}

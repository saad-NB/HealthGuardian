import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Pure-Dart signal utilities (no Flutter/plugin deps, headless-testable).

/// A learned per-bin noise magnitude spectrum (one entry per STFT bin,
/// `fftSize/2 + 1` values). Produced by a calibration pass and applied to later
/// audio by [SpectralDenoiser].
class NoiseProfile {
  const NoiseProfile({
    required this.magnitude,
    required this.fftSize,
    required this.sampleRateHz,
  });

  final Float64List magnitude;
  final int fftSize;
  final int sampleRateHz;
}

/// Streaming spectral-subtraction denoiser (Boll 1979; Berouti et al. 1979).
///
/// The caller records a few seconds of background-only audio first:
/// feed those chunks to [calibrate], call [finalizeCalibration] to get a
/// [NoiseProfile], then either keep processing with the same instance or hand
/// the profile to another instance via [applyProfile] before [process]. Each
/// STFT frame has the learned noise magnitude subtracted from it (with
/// over-subtraction and a spectral floor to avoid musical-noise artefacts) and
/// is overlap-added back to the time domain.
///
/// Output length equals input length (with a fixed [fftSize] latency) so the
/// downstream pipeline's per-chunk timing is preserved. Hann analysis with 50%
/// overlap satisfies the COLA condition, so unmodified frames reconstruct
/// exactly and no window normalization is needed.
class SpectralDenoiser {
  SpectralDenoiser({
    this.sampleRateHz = 16000,
    this.fftSize = 512,
    this.oversubtraction = 2.0,
    this.spectralFloor = 0.05,
  })  : assert((fftSize & (fftSize - 1)) == 0, 'fftSize must be a power of two'),
        hop = fftSize ~/ 2,
        _window = _hann(fftSize) {
    _noisePower = Float64List(fftSize ~/ 2 + 1);
    _re = Float64List(fftSize);
    _im = Float64List(fftSize);
    _ola = Float64List(fftSize);
  }

  final int sampleRateHz;
  final int fftSize;
  final int hop;

  /// Over-subtraction factor alpha: >1 removes more of the noise estimate
  /// (more suppression, more risk of distorting the signal).
  final double oversubtraction;

  /// Spectral floor beta (0..1): the retained fraction of each bin's magnitude,
  /// so a fully-subtracted bin keeps a little energy instead of dropping to a
  /// zero/negative value (which causes musical noise).
  final double spectralFloor;

  final Float64List _window;
  late final Float64List _noisePower;
  Float64List? _noiseMag;
  int _noiseFrames = 0;

  final List<double> _inBuf = [];
  final List<double> _outFifo = [];
  late final Float64List _re;
  late final Float64List _im;
  late final Float64List _ola;

  /// True once a noise profile exists (i.e. [finalizeCalibration] ran with at
  /// least one frame).
  bool get hasProfile => _noiseMag != null;

  /// Number of background frames averaged into the profile.
  int get calibrationFrames => _noiseFrames;

  static Float64List _hann(int n) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n); // periodic Hann
    }
    return w;
  }

  /// Accumulates one chunk of background-only audio (no output).
  void calibrate(Float64List samples) {
    _inBuf.addAll(samples);
    while (_inBuf.length >= fftSize) {
      _analyse();
      for (var k = 0; k < _noisePower.length; k++) {
        _noisePower[k] += _re[k] * _re[k] + _im[k] * _im[k];
      }
      _noiseFrames++;
      _inBuf.removeRange(0, hop);
    }
  }

  /// Averages the accumulated frames into a magnitude profile. Safe to call
  /// with no frames (returns null and leaves [hasProfile] false). Resets the
  /// streaming buffers so measurement output starts clean.
  NoiseProfile? finalizeCalibration() {
    NoiseProfile? profile;
    if (_noiseFrames > 0) {
      final mag = Float64List(_noisePower.length);
      for (var k = 0; k < mag.length; k++) {
        mag[k] = math.sqrt(_noisePower[k] / _noiseFrames);
      }
      _noiseMag = mag;
      profile = NoiseProfile(
        magnitude: mag,
        fftSize: fftSize,
        sampleRateHz: sampleRateHz,
      );
    }
    _inBuf.clear();
    _outFifo.clear();
    _ola.fillRange(0, fftSize, 0);
    return profile;
  }

  /// Uses a previously-learned [profile] (e.g. from a separate calibration
  /// session) for subsequent [process] calls. Ignored if the profile's FFT
  /// geometry doesn't match this denoiser.
  void applyProfile(NoiseProfile profile) {
    if (profile.fftSize != fftSize) return;
    _noiseMag = profile.magnitude;
  }

  /// Denoises [samples]. Returns exactly `samples.length` samples; before the
  /// profile exists it returns the input unchanged.
  Float64List process(Float64List samples) {
    final profile = _noiseMag;
    if (profile == null) return samples;

    _inBuf.addAll(samples);
    while (_inBuf.length >= fftSize) {
      _analyse();
      _subtractAndReconstruct(profile);
      _inBuf.removeRange(0, hop);
    }

    final n = samples.length;
    final out = Float64List(n);
    final take = math.min(n, _outFifo.length);
    for (var i = 0; i < take; i++) {
      out[i] = _outFifo[i];
    }
    if (take > 0) _outFifo.removeRange(0, take);
    return out;
  }

  void reset() {
    _noisePower.fillRange(0, _noisePower.length, 0);
    _noiseMag = null;
    _noiseFrames = 0;
    _inBuf.clear();
    _outFifo.clear();
    _ola.fillRange(0, fftSize, 0);
  }

  /// Windows the first frame of [_inBuf] into [_re]/[_im] and transforms it.
  void _analyse() {
    for (var i = 0; i < fftSize; i++) {
      _re[i] = _inBuf[i] * _window[i];
      _im[i] = 0;
    }
    fft(_re, _im);
  }

  void _subtractAndReconstruct(Float64List profile) {
    final half = fftSize ~/ 2;
    for (var k = 0; k <= half; k++) {
      final reK = _re[k], imK = _im[k];
      final mag = math.sqrt(reK * reK + imK * imK);
      var sub = mag - oversubtraction * profile[k];
      final floor = spectralFloor * mag;
      if (sub < floor) sub = floor;
      final scale = mag > 1e-12 ? sub / mag : 0.0;
      _re[k] = reK * scale;
      _im[k] = imK * scale;
      if (k > 0 && k < half) {
        // Mirror bin: real signal spectra are Hermitian, so keep the
        // conjugate so the inverse transform stays real.
        _re[fftSize - k] *= scale;
        _im[fftSize - k] *= scale;
      }
    }
    _im[0] = 0;
    _im[half] = 0;
    fft(_re, _im, inverse: true);

    for (var i = 0; i < fftSize; i++) {
      _ola[i] += _re[i];
    }
    for (var i = 0; i < hop; i++) {
      _outFifo.add(_ola[i]);
    }
    for (var i = 0; i < fftSize - hop; i++) {
      _ola[i] = _ola[i + hop];
    }
    for (var i = fftSize - hop; i < fftSize; i++) {
      _ola[i] = 0;
    }
  }
}

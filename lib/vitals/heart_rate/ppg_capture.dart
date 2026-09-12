import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// One processed camera frame: the mean red-channel brightness of the central
/// region of interest (fingertip PPG proxy), plus its timestamp.
class PpgSample {
  const PpgSample({required this.redMean, required this.timestampMs});

  final double redMean;
  final double timestampMs;
}

/// Pluggable source of PPG samples. The camera implementation reads real
/// frames; tests substitute synthetic waveforms ([PpgSampleSource] keeps the
/// service headless-testable, ADR-017 §3 "backend swappable").
abstract class PpgSampleSource {
  Future<void> start();
  Stream<PpgSample> get stream;
  Future<void> stop();

  /// Optional live preview of what the sensor sees (camera feed). Null before
  /// the source is initialized. The in-triage HR screen uses this so the user
  /// can verify fingertip coverage while measuring.
  Widget? buildPreview() => null;

  /// Fires when the preview becomes (or stops being) available — e.g. the
  /// camera initialising after the session opens. The UI listens to this so
  /// the live feed appears the moment the sensor is ready, without waiting for
  /// a state change.
  Listenable? get previewListenable => null;

  /// Live diagnostics (label -> value) merged into progress/terminal events.
  Map<String, String> debugSnapshot() => const {};
}

/// Mean-red-channel PPG capture from the rear camera (ADR-017 §4.2).
///
///   - rear camera, lowest [ResolutionPreset.low] (320x240), YUV420 frames;
///   - torch enabled (best-effort — devices without flash degrade to low
///     signal, not a failure) with post-stream verification + retries so a
///     retry after a failed attempt reliably relights the torch;
///   - controller lifetime is strictly serialized: [start] always awaits the
///     previous attempt's disposal, so reopening the camera on "Try again"
///     never races an in-flight close (the camera HAL allows one owner);
///   - exposure + focus locked once started so auto-adjustment doesn't mimic a
///     pulse; the locks run after the stream so torch gain is settled first.
///     White-balance locking is not exposed by the `camera` plugin (0.12), so
///     it is skipped by design;
///   - frames are subsampled centrally at ~[frameIntervalMs] and collapsed to
///     a single mean-red sample using BT.601 R = Y + 1.402·(V−128). Both
///     planar (I420, 3 planes) and interleaved (NV21, 2 planes) layouts are
///     handled; if no chroma plane is usable the luma mean is the fallback.
class PpgCapture extends ChangeNotifier implements PpgSampleSource {
  PpgCapture({this.frameIntervalMs = 33});

  /// Minimum gap between emitted samples (~30 fps).
  final int frameIntervalMs;

  CameraController? _controller;
  StreamController<PpgSample>? _sink;
  final Stopwatch _clock = Stopwatch();
  int _lastEmitMs = 0;
  bool _started = false;
  bool? _torchOn;

  // Guards against reopening the camera while a previous attempt is still
  // being torn down. Every [stop] appends its disposal future here; [start]
  // awaits it before creating a new controller.
  Future<void> _settled = Future<void>.value();

  /// True when the torch is confirmed on (null before first attempt).
  bool? get torchOn => _torchOn;

  @override
  Future<void> start() async {
    if (_started) return;
    await _settled;

    final cameras = await availableCameras();
    CameraDescription? rear;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.back) {
        rear = c;
        break;
      }
    }
    if (rear == null) {
      throw StateError('No rear-facing camera is available on this device.');
    }

    final controller = CameraController(
      rear,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();

    _controller = controller;
    notifyListeners();
    _sink = StreamController<PpgSample>();
    _clock
      ..reset()
      ..start();
    _lastEmitMs = 0;

    // Stream first, then lock the scene and light the torch: on several
    // budget devices a flash command issued before the CameraX stream is
    // running is silently dropped (the "torch won't relight on retry" bug).
    await controller.startImageStream(_onFrame);
    _started = true;
    notifyListeners();

    try {
      await controller.setExposureMode(ExposureMode.locked);
    } catch (_) {}
    try {
      await controller.setFocusMode(FocusMode.locked);
    } catch (_) {}

    await _enableTorch(controller);
  }

  /// Keeps the torch lit even when a setFlashMode call is lost (devices where
  /// the first command after a fresh open is dropped). Confirms via the
  /// plugin's bool result instead of assuming success.
  Future<void> _enableTorch(CameraController controller) async {
    for (var i = 0; i < 6 && _started; i++) {
      try {
        await controller.setFlashMode(FlashMode.torch);
        _torchOn = controller.value.flashMode == FlashMode.torch;
        if (_torchOn == true) return;
      } catch (_) {
        _torchOn = false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _onFrame(CameraImage image) {
    final now = _clock.elapsedMilliseconds;
    if (now - _lastEmitMs < frameIntervalMs) return;
    _lastEmitMs = now;
    _sink?.add(
      PpgSample(
        redMean: _meanRed(image),
        timestampMs: now.toDouble(),
      ),
    );
  }

  /// Mean red over the central ROI (inner 60% of the frame), BT.601. Handles
  /// planar I420 (planes[2] = V) and interleaved NV21 (plane 1 holds V-U
  /// pairs); falls back to mean luma if no chroma is usable.
  double _meanRed(CameraImage image) {
    if (image.format.group != ImageFormatGroup.yuv420) return 0;
    final y = image.planes[0];
    final yBytes = y.bytes;
    final yRow = y.bytesPerRow;

    final w = image.width, h = image.height;
    final x0 = (w * 0.2).round(), x1 = (w * 0.8).round();
    final y0 = (h * 0.2).round(), y1 = (h * 0.8).round();
    const step = 4;

    var sum = 0.0, n = 0;
    final planes = image.planes;

    if (planes.length >= 3) {
      // Planar I420 / YV12: V lives on its own plane.
      final v = planes[2];
      final vRow = v.bytesPerRow;
      for (var yy = y0; yy < y1; yy += step) {
        final yRowBase = yy * yRow;
        final vRowBase = (yy >> 1) * vRow;
        for (var xx = x0; xx < x1; xx += step) {
          final luma = yBytes[yRowBase + xx];
          final cr = v.bytes[vRowBase + (xx >> 1)];
          sum += luma + 1.402 * (cr - 128);
          n++;
        }
      }
    } else if (planes.length == 2) {
      // Interleaved chroma. Android's NV21 stores V,U per pair (target); iOS
      // bi-planar 420f stores U,V — V is the neighbour byte accordingly.
      final uv = planes[1];
      final uvRow = uv.bytesPerRow;
      final vFirst = !Platform.isIOS;
      for (var yy = y0; yy < y1; yy += step) {
        final yRowBase = yy * yRow;
        final uvRowBase = (yy >> 1) * uvRow;
        for (var xx = x0; xx < x1; xx += step) {
          final luma = yBytes[yRowBase + xx];
          final base = uvRowBase + ((xx >> 1) << 1);
          final cr = vFirst ? uv.bytes[base] : uv.bytes[base + 1];
          sum += luma + 1.402 * (cr - 128);
          n++;
        }
      }
    } else {
      // No chroma: mean luma still carries the pulse modulation.
      for (var yy = y0; yy < y1; yy += step) {
        final yRowBase = yy * yRow;
        for (var xx = x0; xx < x1; xx += step) {
          sum += yBytes[yRowBase + xx];
          n++;
        }
      }
    }

    if (n == 0) return 0;
    return sum / n;
  }

  @override
  Stream<PpgSample> get stream => _sink!.stream;

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _torchOn = false;
    final teardown = _dispose();
    _settled = teardown;
    await teardown;
  }

  Future<void> _dispose() async {
    final controller = _controller;
    _controller = null;
    notifyListeners();
    final sink = _sink;
    _sink = null;
    if (controller != null) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      // Explicitly kill the torch before release — some HALs keep it burning
      // after a bare dispose if the stream was still live.
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
    _clock.stop();
    if (sink != null && !sink.isClosed) {
      await sink.close();
    }
  }

  @override
  Widget? buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraPreview(controller);
  }

  @override
  Listenable get previewListenable => this;

  @override
  Map<String, String> debugSnapshot() {
    final controller = _controller;
    return {
      'camera': controller == null ? '—' : (_started ? 'recording' : 'ready'),
      'torch': _torchOn == null ? 'unknown' : (_torchOn! ? 'on' : 'OFF'),
    };
  }

  @override
  String toString() => 'PpgCapture(frameIntervalMs=$frameIntervalMs)';
}
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../dsp/spectral_denoise.dart';
import 'breath_capture.dart';

/// Events a background-noise calibration emits.
sealed class CalibrationEvent {
  const CalibrationEvent();
}

/// Periodic progress while recording the background (seconds elapsed / total).
class CalibrationProgress extends CalibrationEvent {
  const CalibrationProgress(this.elapsedSeconds, this.totalSeconds);

  final double elapsedSeconds;
  final double totalSeconds;
}

/// Calibration finished; [profile] is ready to apply to a measurement.
class CalibrationDone extends CalibrationEvent {
  const CalibrationDone(this.profile);

  final NoiseProfile profile;
}

/// Calibration could not run or heard nothing usable.
class CalibrationFailed extends CalibrationEvent {
  const CalibrationFailed(this.reason);

  final String reason;
}

/// Records a few seconds of background-only audio and turns it into a
/// [NoiseProfile] for [SpectralDenoiser].
///
/// Deliberately separate from [BreathingRateService]: the user learns the
/// room's noise first, and the accepted profile is reused by every following
/// breath measurement (see `NoiseProfileStore`). This keeps the breath
/// countdown from ever being shown before/while the background is recorded.
class BreathingCalibrationService {
  BreathingCalibrationService({
    BreathChunkSource Function()? sourceFactory,
    this.calibrationSeconds = 6,
    SpectralDenoiser? denoiser,
  })  : _sourceFactory = sourceFactory ?? (() => BreathCapture()),
        _denoiser = denoiser ?? SpectralDenoiser();

  final BreathChunkSource Function() _sourceFactory;
  final double calibrationSeconds;
  final SpectralDenoiser _denoiser;

  Stream<CalibrationEvent> run() async* {
    final source = _sourceFactory();
    try {
      await source.start();
    } catch (e) {
      yield CalibrationFailed('Could not start the microphone: $e');
      return;
    }

    var lastSecond = -1;
    try {
      await for (final chunk in source.stream) {
        _denoiser.calibrate(chunk.samples);
        final sec = chunk.elapsedSeconds.floor();
        if (sec != lastSecond) {
          lastSecond = sec;
          yield CalibrationProgress(chunk.elapsedSeconds, calibrationSeconds);
        }
        if (chunk.elapsedSeconds >= calibrationSeconds) break;
      }
    } finally {
      // Fire-and-forget teardown so emission is never blocked on the sensor.
      unawaited(source.stop());
    }

    final profile = _denoiser.finalizeCalibration();
    if (profile == null) {
      yield const CalibrationFailed(
        'Could not hear enough background to learn a noise profile.',
      );
      return;
    }
    debugPrint('HG_RR_CAL frames=${_denoiser.calibrationFrames}');
    yield CalibrationDone(profile);
  }
}

import 'dart:async';

import '../models.dart';
import 'breath_capture.dart';
import 'breath_pipeline.dart';

/// Tunable service-level RR constants (mirrors VITALS_SENSING §5.2).
class BreathingRateServiceConfig {
  const BreathingRateServiceConfig({
    this.sessionSeconds = 45,
    this.minUsableSeconds = 30,
    this.detrendSeconds = 15,
  });

  final int sessionSeconds;
  final int minUsableSeconds;

  /// Length (s) of the envelope detrend moving average. It is also the
  /// settle-in time before envelope values are trusted for period detection,
  /// so longer feeds want the product default (15 s) and short synthetic
  /// tests shorten it.
  final double detrendSeconds;
}

/// Drives the microphone capture through [BreathPipeline] and emits the
/// session event stream the UI consumes (progress each second, then a
/// [MeasurementSuccess] reading or a [MeasurementInsufficient]).
///
/// Framing decisions:
///  - the "useful" RR band is 4-60 breaths/min; too-loud rooms, below-band or
///    too-noisy signals end in [MeasurementInsufficient], never a forced
///    number (ADR-017 §6);
///  - ends [sessionSeconds] after starting, or early once the pipeline reports
///    enough stable usable coverage (RR is slow, so the bar is high);
///  - the source factory is injectable so tests stream synthetic waveforms.
class BreathingRateService {
  BreathingRateService({
    BreathChunkSource Function()? sourceFactory,
    BreathPipeline? pipeline,
    BreathingRateServiceConfig config = const BreathingRateServiceConfig(),
  })  : _sourceFactory = sourceFactory ?? (() => BreathCapture()),
        _pipeline =
            pipeline ?? BreathPipeline(config: BreathConfig(
          minUsableSeconds: config.minUsableSeconds,
          earlyFinishUsableSeconds: config.minUsableSeconds >= 6
              ? config.minUsableSeconds - 2
              : 4,
          detrendSeconds: config.detrendSeconds,
        )),
        _config = config;

  final BreathChunkSource Function() _sourceFactory;
  final BreathPipeline _pipeline;
  final BreathingRateServiceConfig _config;

  Stream<MeasurementEvent> run() => _measure();

  Stream<MeasurementEvent> _measure() async* {
    final clock = Stopwatch()..start();
    final source = _sourceFactory();

    try {
      await source.start();
    } catch (e) {
      yield MeasurementFailed('Could not start the microphone: $e');
      return;
    }

    var lastSecond = -1;
    try {
      await for (final chunk in source.stream) {
        _pipeline.add(
          samples: chunk.samples,
          elapsedSeconds: chunk.elapsedSeconds,
        );

        final sec = clock.elapsed.inSeconds;
        if (sec == lastSecond) continue;
        lastSecond = sec;

        final est = _pipeline.estimate();
        yield MeasurementProgress(
          sec.toDouble(),
          instantValue: est?.cpm,
        );

        if (_pipeline.earlyFinishEligible()) break;
        if (sec >= _config.sessionSeconds) break;
      }
    } finally {
      // Fire-and-forget teardown so we never block emission on sensor teardown
      // (mirrors MeasurementSession._stop policy).
      unawaited(source.stop());
    }

    final est = _pipeline.estimate();
    if (est == null || est.usableSeconds < _config.minUsableSeconds) {
      yield MeasurementInsufficient(
        _pipeline.ambientNoisy
            ? 'The room is too loud to count breaths. Keep the surroundings '
                'quiet and try again.'
            : _pipeline.subBandDominant
                ? 'The signal is below the breathing screening band '
                    '(4-60 breaths/min).'
                : 'No reliable breathing signal detected. Place the phone '
                    'near the patient\'s mouth and nose, then try again.',
      );
      return;
    }

    yield MeasurementSuccess(
      VitalReading(
        kind: VitalKind.breathingRate,
        value: est.cpm,
        confidence: est.confidence,
        measuredAt: DateTime.now(),
        note: est.note,
      ),
    );
  }
}
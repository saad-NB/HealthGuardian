import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

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

  /// One line of `debugPrint` output -> `adb logcat` (tag "flutter").
  /// `tools/hr_log.dart` collects and analyzes HG_RR lines to recalibrate the
  /// confidence gates from real device signal and to see WHICH gate killed a
  /// reading (VITALS_SENSING §4.2 "diagnostics", DECISIONS).
  Map<String, Object?> _logEntry({
    required String type,
    required int sec,
    Object? outcome,
    Object? cpm,
    Object? confidence,
    String? reason,
  }) {
    final d = _pipeline.debugSnapshot();
    return {
      'v': 1,
      'type': type,
      'sec': sec,
      'outcome': outcome,
      'cpm': cpm ?? (d['cpm'] == '—' ? null : num.tryParse(d['cpm']!)),
      'conf': confidence,
      'reg': num.tryParse(d['reg']!),
      'corr': num.tryParse(d['corr']!),
      'amp': num.tryParse(d['amp']!),
      'q': num.tryParse(d['quality']!),
      'usable': d['usable'] == '—'
          ? null
          : int.tryParse(d['usable']!.replaceAll('s', '')),
      'ibis': num.tryParse(d['ibis']!),
      'lag': d['lag_ms'] == '—' ? null : num.tryParse(d['lag_ms']!),
      'peaks': int.tryParse(d['peaks']!),
      'peak': d['peak_amp'] == '—' ? null : num.tryParse(d['peak_amp']!),
      'band': num.tryParse(d['band_rms']!),
      'raw': num.tryParse(d['raw']!),
      'breath': d['breath'] == 'yes',
      'noisy': d['noisy'] == 'yes',
      'sub': d['sub_band'] == 'yes',
      'env_sub': d['env_sub'] == 'yes',
      'reason': ?reason,
    };
  }

  Stream<MeasurementEvent> _measure() async* {
    final clock = Stopwatch()..start();
    final source = _sourceFactory();

    try {
      await source.start();
    } catch (e) {
      debugPrint(
          'HG_RR ${jsonEncode(_logEntry(type: 'f', sec: 0, outcome: 'failed'))}');
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
        debugPrint(
          'HG_RR ${jsonEncode(_logEntry(type: 'p', sec: sec, cpm: est?.cpm))}',
        );
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
      final reason = _pipeline.ambientNoisy
          ? 'noisy'
          : _pipeline.subBandDominant
              ? 'sub'
              : _pipeline.envelopeSubBandDominant
                  ? 'env_sub'
                  : est == null
                      ? (_pipeline.hasBreath ? 'no-validate' : 'no-breath')
                      : 'short';
      debugPrint(
        'HG_RR ${jsonEncode(_logEntry(
          type: 'f',
          sec: lastSecond.clamp(0, 99999),
          outcome: 'insufficient',
          reason: reason,
        ))}',
      );
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

    debugPrint(
      'HG_RR ${jsonEncode(_logEntry(
        type: 'f',
        sec: lastSecond.clamp(0, 99999),
        outcome: 'ok',
        cpm: est.cpm,
        confidence: est.confidence.toString(),
      ))}',
    );
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
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models.dart';
import 'ppg_capture.dart';
import 'ppg_pipeline.dart';

/// Tunable service-level HR constants (mirrors VITALS_SENSING §4.2).
class HeartRateServiceConfig {
  const HeartRateServiceConfig({
    this.sessionSeconds = 30,
    this.sampleRateHz = 30,
    this.minUsableSeconds = 14,
  });

  final int sessionSeconds;
  final double sampleRateHz;
  final int minUsableSeconds;
}

/// Drives the camera PPG capture through [PpgPipeline] and emits the session
/// event stream the UI consumes (progress each second, then a
/// [MeasurementSuccess] reading or a [MeasurementInsufficient]).
///
/// Framing decisions:
///  - the "useful" HR band is 42-210 bpm; below-band or too-noisy signals end
///    in [MeasurementInsufficient], never a forced number (ADR-017 §6);
///  - ends [sessionSeconds] after starting, or early once the pipeline reports
///    enough stable usable coverage;
///  - the source factory is injectable so tests stream synthetic waveforms.
class HeartRateService {
  HeartRateService({
    PpgSampleSource Function()? sourceFactory,
    PpgPipeline? pipeline,
    HeartRateServiceConfig config = const HeartRateServiceConfig(),
  })  : _sourceFactory = sourceFactory ?? (() => PpgCapture()),
        _pipeline = pipeline ??
            PpgPipeline(
              config: PpgConfig(
                sampleRateHz: config.sampleRateHz,
                minUsableSeconds: config.minUsableSeconds,
                earlyFinishUsableSeconds:
                    config.minUsableSeconds >= 6 ? config.minUsableSeconds - 2 : 4,
              ),
            ),
        _config = config;

  final PpgSampleSource Function() _sourceFactory;
  final PpgPipeline _pipeline;
  final HeartRateServiceConfig _config;

  PpgSampleSource? _source;

  Stream<MeasurementEvent> run() => _measure();

  /// One line of `debugPrint` output → `adb logcat` (tag "flutter"). `tools/hr_log.dart`
  /// collects and analyzes these to recalibrate the confidence thresholds from
  /// real device signal (VITALS_SENSING §4.2 "diagnostics", DECISIONS).
  Map<String, Object?> _logEntry({
    required String type,
    required int sec,
    Object? outcome,
    Object? bpm,
    Object? confidence,
  }) {
    final d = _pipeline.debugSnapshot();
    return {
      'v': 1,
      'type': type,
      'sec': sec,
      'outcome': outcome,
      'bpm': bpm ?? (d['bpm'] == '—' ? null : num.tryParse(d['bpm']!)),
      'conf': confidence,
      'reg': num.tryParse(d['reg']!),
      'corr': num.tryParse(d['corr']!),
      'amp': num.tryParse(d['amp']!),
      'drift': d['drift'] == '—' ? null : num.tryParse(d['drift']!),
      'q': num.tryParse(d['quality']!),
      'usable': d['usable'] == '—'
          ? null
          : int.tryParse(d['usable']!.replaceAll('s', '')),
      'sub': d['sub_band'] == 'yes',
    };
  }

  Stream<MeasurementEvent> _measure() async* {
    // Retries must start from a blank slate — the pipeline is a field shared
    // across attempts, so throw away any previous IBIs/coverage.
    _pipeline.reset();

    final clock = Stopwatch()..start();
    final source = _sourceFactory();
    _source = source;

    try {
      await source.start();
    } catch (e) {
      debugPrint('HG_HR ${jsonEncode(_logEntry(type: 'f', sec: 0, outcome: 'failed'))}');
      yield MeasurementFailed('Could not start the camera: $e');
      return;
    }

    var lastSecond = -1;
    try {
      await for (final sample in source.stream) {
        _pipeline.add(
          timestampMs: sample.timestampMs,
          redMean: sample.redMean,
        );

        final sec = clock.elapsed.inSeconds;
        if (sec == lastSecond) continue;
        lastSecond = sec;

        final est = _pipeline.estimate();
        debugPrint(
          'HG_HR ${jsonEncode(_logEntry(type: 'p', sec: sec, bpm: est?.bpm))}',
        );
        yield MeasurementProgress(
          sec.toDouble(),
          instantValue: est?.bpm,
          debug: _debugNow(),
        );

        if (_pipeline.earlyFinishEligible()) break;
        if (sec >= _config.sessionSeconds) break;
      }
    } finally {
      // Fire-and-forget teardown so we never block emission on sensor teardown
      // (mirrors MeasurementSession._stop policy; real activity is awaited by
      // the service caller only for lifecycle sanity).
      unawaited(source.stop());
    }

    final est = _pipeline.estimate();
    if (est == null ||
        est.usableSeconds < _config.minUsableSeconds) {
      debugPrint(
        'HG_HR ${jsonEncode(_logEntry(
          type: 'f',
          sec: lastSecond.clamp(0, 99999),
          outcome: 'insufficient',
        ))}',
      );
      yield MeasurementInsufficient(
        _pipeline.subBandDominant
            ? 'The signal is below the pulse screening band (42-210 bpm).'
            : 'No reliable pulse signal detected. Cover the lens fully and '
                'hold very still.',
        debug: _debugNow(),
      );
      return;
    }

    debugPrint(
      'HG_HR ${jsonEncode(_logEntry(
        type: 'f',
        sec: lastSecond.clamp(0, 99999),
        outcome: 'ok',
        bpm: est.bpm,
        confidence: est.confidence.toString(),
      ))}',
    );
    yield MeasurementSuccess(
      VitalReading(
        kind: VitalKind.heartRate,
        value: est.bpm,
        confidence: est.confidence,
        measuredAt: DateTime.now(),
        note: est.note,
      ),
    );
  }

  Map<String, String> _debugNow() {
    final res = _source?.debugSnapshot() ?? const <String, String>{};
    return {...res, ..._pipeline.debugSnapshot()};
  }
}
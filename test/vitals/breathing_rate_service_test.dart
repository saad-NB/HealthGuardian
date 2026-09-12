import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/breathing_rate/breath_capture.dart';
import 'package:healthguardian/vitals/breathing_rate/breathing_rate_service.dart';
import 'package:healthguardian/vitals/breathing_rate/noise_profile_store.dart';
import 'package:healthguardian/vitals/dsp/spectral_denoise.dart';
import 'package:healthguardian/vitals/models.dart';

const _sampleRateHz = 16000.0;

Float64List _synth({
  required double cpm,
  required double seconds,
  double amplitude = 0.05,
  double ambient = 0,
  double carrierHz = 550,
  int seed = 3,
}) {
  final n = (seconds * _sampleRateHz).round();
  final out = Float64List(n);
  final f = cpm / 60;
  final rng = math.Random(seed);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRateHz;
    final env = amplitude * (0.75 + 0.25 * math.sin(2 * math.pi * f * t));
    var v = math.sin(2 * math.pi * carrierHz * t) * env;
    if (ambient > 0) v += ambient * (rng.nextDouble() * 2 - 1);
    out[i] = v;
  }
  return out;
}

class _FakeBreathSource implements BreathChunkSource {
  _FakeBreathSource(this.pcm, {this.failStart = false});

  final Float64List pcm;
  final bool failStart;
  final StreamController<BreathChunk> _ctrl = StreamController<BreathChunk>();

  @override
  Future<void> start() async {
    if (failStart) {
      throw StateError('no microphone available');
    }
    const chunk = 4096;
    for (var off = 0; off < pcm.length; off += chunk) {
      final end = math.min(off + chunk, pcm.length);
      _ctrl.add(
        BreathChunk(
          samples: Float64List.sublistView(pcm, off, end),
          elapsedSeconds: end / _sampleRateHz,
        ),
      );
    }
    // Not awaited: close()'s future only completes once a listener consumes
    // the buffered events, and the service subscribes after start().
    _ctrl.close();
  }

  @override
  Stream<BreathChunk> get stream => _ctrl.stream;

  @override
  Future<void> stop() async {}
}

Future<List<MeasurementEvent>> _run(BreathingRateService service) async {
  return service.run().toList();
}

void main() {
  setUp(NoiseProfileStore.clear);

  const short = BreathingRateServiceConfig(
    sessionSeconds: 20,
    minUsableSeconds: 12,
    detrendSeconds: 6,
  );

  test('success path emits progress then a confident reading', () async {
    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(_synth(cpm: 15, seconds: 30)),
    );
    final events = await _run(service);

    expect(events.first, isA<MeasurementProgress>());
    final success = events.last;
    expect(success, isA<MeasurementSuccess>());
    final reading = (success as MeasurementSuccess).reading;
    expect(reading.kind, VitalKind.breathingRate);
    expect(reading.value, closeTo(15, 3));
    expect(reading.confidence, isNot(ReadingConfidence.low));
    expect(reading.measuredAt, isNotNull);
  });

  test('insufficient when no breath signal is found', () async {
    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(
        _synth(cpm: 15, seconds: 24, amplitude: 0),
      ),
    );
    final events = await _run(service);
    expect(events.last, isA<MeasurementInsufficient>());
    expect((events.last as MeasurementInsufficient).reason,
        contains('breathing'));
  });

  test('loud room yields a quiet-surroundings insufficient', () async {
    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(
        _synth(cpm: 15, seconds: 24, amplitude: 1e-6, ambient: 0.09),
      ),
    );
    final events = await _run(service);
    expect(events.last, isA<MeasurementInsufficient>());
    expect((events.last as MeasurementInsufficient).reason,
        contains('quiet'));
  });

  test('applies a stored noise profile without disturbing detection', () async {
    // Learn a profile from synthetic background, then measure clean breathing.
    final calibrator = SpectralDenoiser();
    calibrator.calibrate(
      _synth(cpm: 0, seconds: 1, amplitude: 1e-6, ambient: 0.02, seed: 1),
    );
    final profile = calibrator.finalizeCalibration();
    expect(profile, isNotNull);
    NoiseProfileStore.set(profile!);

    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(_synth(cpm: 15, seconds: 30)),
    );
    final events = await _run(service);
    expect(events.last, isA<MeasurementSuccess>());
    expect(
      (events.last as MeasurementSuccess).reading.value,
      closeTo(15, 3),
    );
  });

  test('capture failures surface as MeasurementFailed', () async {
    final service = BreathingRateService(
      config: short,
      sourceFactory: () =>
          _FakeBreathSource(Float64List(0), failStart: true),
    );
    final events = await _run(service);
    expect(events, hasLength(1));
    expect(events.single, isA<MeasurementFailed>());
    expect((events.single as MeasurementFailed).reason,
        contains('microphone'));
  });

  test('success emits per-second progress + an "ok" HG_RR final line',
      () async {
    final lines = <String>[];
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        lines.add(message ?? '');
    addTearDown(() => debugPrint = prev);

    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(_synth(cpm: 15, seconds: 30)),
    );
    await service.run().toList();

    final log = lines
        .where((l) => l.startsWith('HG_RR '))
        .map(
          (l) => (jsonDecode(l.substring('HG_RR '.length)) as Map)
              .cast<String, Object?>(),
        )
        .toList();
    expect(log, isNotEmpty);
    expect(log.any((e) => e['type'] == 'p' && e['q'] is num), isTrue);
    final fin = log.lastWhere((e) => e['type'] == 'f');
    expect(fin['outcome'], 'ok');
    expect(fin['cpm'], isNotNull);
    expect(fin['usable'], isNotNull);
  });

  test('loud room emits an insufficient HG_RR final with reason noisy',
      () async {
    final service = BreathingRateService(
      config: short,
      sourceFactory: () => _FakeBreathSource(
        _synth(cpm: 15, seconds: 12, amplitude: 1e-6, ambient: 0.09),
      ),
    );
    final lines = <String>[];
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        lines.add(message ?? '');
    addTearDown(() => debugPrint = prev);
    await service.run().toList();

    final f = lines
        .where((l) => l.startsWith('HG_RR '))
        .map(
          (l) => (jsonDecode(l.substring('HG_RR '.length)) as Map)
              .cast<String, Object?>(),
        )
        .lastWhere((e) => e['type'] == 'f');
    expect(f['outcome'], 'insufficient');
    expect(f['reason'], 'noisy');
  });
}
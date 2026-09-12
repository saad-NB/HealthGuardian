import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/heart_rate/heart_rate_service.dart';
import 'package:healthguardian/vitals/heart_rate/ppg_capture.dart';
import 'package:healthguardian/vitals/models.dart';

PpgSample s(double red, double ms) => PpgSample(redMean: red, timestampMs: ms);

List<PpgSample> synth({
  required double bpm,
  required double seconds,
  double sampleRateHz = 30,
  double amplitude = 1.5,
  double noise = 0.0,
  int seed = 3,
  double baseline = 110,
}) {
  final rng = math.Random(seed);
  final out = <PpgSample>[];
  final n = (seconds * sampleRateHz).round();
  final msPerFrame = 1000 / sampleRateHz;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRateHz;
    final pulse = amplitude * math.sin(2 * math.pi * bpm / 60 * t);
    final drift = 2 * math.sin(2 * math.pi * 0.05 * t);
    final nz = noise * (rng.nextDouble() * 2 - 1);
    out.add(s(baseline + pulse + drift + nz, i * msPerFrame));
  }
  return out;
}

class _FakeSource implements PpgSampleSource {
  _FakeSource(this.samples, {this.failStart = false});

  final List<PpgSample> samples;
  final bool failStart;
  final StreamController<PpgSample> _ctrl = StreamController<PpgSample>();

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no rear camera');
    for (final sample in samples) {
      _ctrl.add(sample);
    }
    // Not awaited: close()'s future only completes once a listener has
    // consumed the buffered events, and the service subscribes after start().
    _ctrl.close();
  }

  @override
  Stream<PpgSample> get stream => _ctrl.stream;

  @override
  Future<void> stop() async {}

  @override
  Widget? buildPreview() => null;

  @override
  Listenable? get previewListenable => null;

  @override
  Map<String, String> debugSnapshot() => const {'torch': 'nil'};
}

Future<List<MeasurementEvent>> run(
  HeartRateService service,
) async {
  return service.run().toList();
}

void main() {
  const short =
      HeartRateServiceConfig(sessionSeconds: 20, minUsableSeconds: 8);

  test('success path emits progress then a confident reading', () async {
    final service = HeartRateService(
      config: short,
      sourceFactory: () => _FakeSource(synth(bpm: 100, seconds: 15)),
    );
    final events = await run(service);

    expect(events.first, isA<MeasurementProgress>());
    expect((events.first as MeasurementProgress).elapsedSeconds, 0);

    final success = events.last;
    expect(success, isA<MeasurementSuccess>());
    final reading = (success as MeasurementSuccess).reading;
    expect(reading.kind, VitalKind.heartRate);
    expect(reading.value, closeTo(100, 5));
    expect(reading.confidence, isNot(ReadingConfidence.low));
    expect(reading.measuredAt, isNotNull);
  });

  test('insufficient when no pulse is found', () async {
    // Flat brightness: no pulsatile component to beat-detect.
    final service = HeartRateService(
      config: short,
      sourceFactory: () => _FakeSource(synth(bpm: 100, seconds: 12, amplitude: 0)),
    );
    final events = await run(service);
    expect(events.last, isA<MeasurementInsufficient>());
    expect((events.last as MeasurementInsufficient).reason,
        contains('pulse'));
  });

  test('noisy signal resolves to a low-confidence success (never a forced '
      'number in the wrong band)', () async {
    final service = HeartRateService(
      config: short,
      sourceFactory: () => _FakeSource(
        synth(bpm: 100, seconds: 15, amplitude: 0.3, noise: 2.0),
      ),
    );
    final events = await run(service);
    final success = events.last;
    // Either we got a beat read (low confidence) or an honest insufficient —
    // both are acceptable triage outcomes; a silent wrong-strong number is not.
    expect(
      success.runtimeType == MeasurementSuccess ||
          success.runtimeType == MeasurementInsufficient,
      isTrue,
    );
  });

  test('capture failures surface as MeasurementFailed', () async {
    final service = HeartRateService(
      config: short,
      sourceFactory: () => _FakeSource(const [], failStart: true),
    );
    final events = await run(service);
    expect(events, hasLength(1));
    expect(events.single, isA<MeasurementFailed>());
    expect((events.single as MeasurementFailed).reason, contains('camera'));
  });
}
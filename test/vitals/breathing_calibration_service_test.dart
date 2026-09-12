import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/breathing_rate/breath_capture.dart';
import 'package:healthguardian/vitals/breathing_rate/breathing_calibration_service.dart';

const _sr = 16000.0;

Float64List _noise({required double seconds, int seed = 1}) {
  final n = (seconds * _sr).round();
  final out = Float64List(n);
  final rng = math.Random(seed);
  for (var i = 0; i < n; i++) {
    out[i] = 0.02 * (rng.nextDouble() * 2 - 1);
  }
  return out;
}

class _FakeSource implements BreathChunkSource {
  _FakeSource(this.pcm, {this.failStart = false});

  final Float64List pcm;
  final bool failStart;
  final StreamController<BreathChunk> _ctrl = StreamController<BreathChunk>();

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no microphone available');
    const chunk = 4096;
    for (var off = 0; off < pcm.length; off += chunk) {
      final end = math.min(off + chunk, pcm.length);
      _ctrl.add(
        BreathChunk(
          samples: Float64List.sublistView(pcm, off, end),
          elapsedSeconds: end / _sr,
        ),
      );
    }
    _ctrl.close();
  }

  @override
  Stream<BreathChunk> get stream => _ctrl.stream;

  @override
  Future<void> stop() async {}
}

void main() {
  test('learns a noise profile and reports progress', () async {
    final service = BreathingCalibrationService(
      calibrationSeconds: 2,
      sourceFactory: () => _FakeSource(_noise(seconds: 3)),
    );
    final events = await service.run().toList();

    expect(events.whereType<CalibrationProgress>(), isNotEmpty);
    final done = events.last;
    expect(done, isA<CalibrationDone>());
    final profile = (done as CalibrationDone).profile;
    expect(profile.fftSize, 512);
    expect(profile.magnitude.length, 257);
    expect(profile.magnitude.any((v) => v > 0), isTrue);
  });

  test('fails cleanly when the microphone cannot start', () async {
    final service = BreathingCalibrationService(
      sourceFactory: () => _FakeSource(Float64List(0), failStart: true),
    );
    final events = await service.run().toList();
    expect(events.single, isA<CalibrationFailed>());
    expect((events.single as CalibrationFailed).reason,
        contains('microphone'));
  });

  test('fails when no audio is captured', () async {
    final service = BreathingCalibrationService(
      sourceFactory: () => _FakeSource(Float64List(0)),
    );
    final events = await service.run().toList();
    expect(events.single, isA<CalibrationFailed>());
  });
}

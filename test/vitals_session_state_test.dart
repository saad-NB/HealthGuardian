import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/measurement_session.dart';
import 'package:healthguardian/vitals/models.dart';

void main() {
  VitalReading reading(double v, {ReadingConfidence c = ReadingConfidence.high}) =>
      VitalReading(
        kind: VitalKind.heartRate,
        value: v,
        confidence: c,
        measuredAt: DateTime(2026, 9, 11, 12),
      );

  group('MeasurementSession state machine', () {
    test('fails closed when permission is denied, with an actionable message',
        () async {
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => false,
        run: () => const Stream<MeasurementEvent>.empty(),
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.failed);
      expect(session.message, contains('camera'));
      expect(session.message, contains('Settings'));
    });

    test('progress updates elapsed time and the countdown fraction', () async {
      final controller = StreamController<MeasurementEvent>();
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => controller.stream,
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      controller.add(const MeasurementProgress(5));
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.measuring);
      expect(session.elapsedSeconds, 5);
      expect(session.progress, closeTo(5 / 30, 0.001));
      await controller.close();
      session.dispose();
    });

    test('a success event ends the session with the reading', () async {
      final controller = StreamController<MeasurementEvent>();
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => controller.stream,
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      controller.add(MeasurementSuccess(reading(72)));
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.success);
      expect(session.hasReading, isTrue);
      expect(session.reading!.value, 72);
      // subscription torn down after the terminal event
      expect(controller.hasListener, isFalse);
      await controller.close();
      session.dispose();
    });

    test('low-confidence readings still succeed but are flagged acceptable',
        () {
      expect(ReadingConfidence.low.isAcceptableOnItsOwn, isFalse);
      expect(ReadingConfidence.medium.isAcceptableOnItsOwn, isTrue);
      expect(ReadingConfidence.high.isAcceptableOnItsOwn, isTrue);
    });

    test('insufficient-signal transitions without a reading', () async {
      final controller = StreamController<MeasurementEvent>();
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => controller.stream,
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      controller.add(const MeasurementInsufficient('Too much movement detected'));
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.insufficientSignal);
      expect(session.hasReading, isFalse);
      expect(session.message, 'Too much movement detected');
      await controller.close();
      session.dispose();
    });

    test('retry re-runs the measurement service (fresh stream per attempt)',
        () async {
      var runs = 0;
      late StreamController<MeasurementEvent> controller;
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () {
          runs++;
          controller = StreamController<MeasurementEvent>();
          return controller.stream;
        },
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      controller.add(const MeasurementInsufficient('weak signal'));
      await Future<void>.delayed(Duration.zero);
      expect(runs, 1);
      session.retry();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
      controller.add(MeasurementSuccess(reading(80)));
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.success);
      await controller.close();
      session.dispose();
    });

    test('cancel stops measuring and marks the session cancelled', () async {
      final controller = StreamController<MeasurementEvent>();
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => controller.stream,
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.measuring);
      await session.cancel();
      expect(session.phase, SessionPhase.cancelled);
      expect(controller.hasListener, isFalse);
      await controller.close();
      session.dispose();
    });

    test('positionsFirst parks in positioning until beginMeasure (no timer)',
        () async {
      var cameraStarts = 0;
      final controller = StreamController<MeasurementEvent>();
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => controller.stream,
        positionsFirst: true,
        beginPositioning: () async {
          cameraStarts++;
          await Future<void>.delayed(Duration.zero);
        },
        endPositioning: () async {},
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.positioning);
      expect(cameraStarts, 1);
      expect(controller.hasListener, isFalse); // no countdown running yet

      session.beginMeasure();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.measuring);
      controller.add(const MeasurementProgress(3));
      await Future<void>.delayed(Duration.zero);
      expect(session.elapsedSeconds, 3);

      await controller.close();
      session.dispose();
    });

    test('abandoning from positioning stops the positioning camera', () async {
      var cameraStops = 0;
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => const Stream<MeasurementEvent>.empty(),
        positionsFirst: true,
        beginPositioning: () async {},
        endPositioning: () async {
          cameraStops++;
        },
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.positioning);
      await session.cancel();
      expect(cameraStops, 1);
      expect(session.phase, SessionPhase.cancelled);
      session.dispose();
    });

    test('retry after insufficient returns to positioning when positionsFirst',
        () async {
      var runs = 0;
      late StreamController<MeasurementEvent> controller;
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () {
          runs++;
          controller = StreamController<MeasurementEvent>();
          return controller.stream;
        },
        positionsFirst: true,
        beginPositioning: () async {},
        endPositioning: () async {},
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.positioning);
      session.beginMeasure();
      await Future<void>.delayed(Duration.zero);
      controller.add(const MeasurementInsufficient('weak signal'));
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.insufficientSignal);

      session.retry();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.positioning, reason: 're-place finger');
      expect(runs, 1); // service not re-run until the user taps start
      await controller.close();
      session.dispose();
    });

    test('positioning camera failure surfaces as failed', () async {
      final session = MeasurementSession(
        kind: VitalKind.heartRate,
        ensureAccess: (_) async => true,
        run: () => const Stream<MeasurementEvent>.empty(),
        positionsFirst: true,
        beginPositioning: () async {
          throw StateError('no rear camera');
        },
      );
      session.start();
      await Future<void>.delayed(Duration.zero);
      expect(session.phase, SessionPhase.failed);
      expect(session.message, contains('no rear camera'));
      session.dispose();
    });
  });
}
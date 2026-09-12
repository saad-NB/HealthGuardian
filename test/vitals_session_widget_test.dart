import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/measurement_session.dart';
import 'package:healthguardian/vitals/measurement_session_view.dart';
import 'package:healthguardian/vitals/models.dart';

void main() {
  VitalReading reading(
    double v, {
    ReadingConfidence c = ReadingConfidence.high,
    String? note,
  }) =>
      VitalReading(
        kind: VitalKind.heartRate,
        value: v,
        confidence: c,
        measuredAt: DateTime(2026, 9, 11, 12),
        note: note,
      );

  final disclaim =
      find.textContaining('Screening estimate only');

  // NOTE: widget tests use BROADCAST controllers on purpose. Cancelling a
  // single-subscription stream inside its own onData callback and then calling
  // close() deadlocks the FakeAsync test clock (flutter_test teardown); the
  // real HR/RR services run in real async, which the pure-Dart state tests
  // cover with single-subscription streams.
  Widget appWith({
    required MeasurementSession session,
    ValueChanged<VitalReading?>? onResult,
  }) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await launchMeasurementSession(
                  context,
                  session: session,
                  cancelLabel: 'Enter manually instead',
                );
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('measuring phase shows instruction + countdown', (tester) async {
    final controller = StreamController<MeasurementEvent>.broadcast();
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.textContaining('fingertip'), findsOneWidget);
    expect(find.textContaining('remaining'), findsOneWidget);
    await controller.close();
  });

  testWidgets('medium confidence is accepted via "Use this reading"',
      (tester) async {
    final controller = StreamController<MeasurementEvent>.broadcast();
    VitalReading? result;
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
    );
    await tester
        .pumpWidget(appWith(session: session, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    controller.add(MeasurementSuccess(
        reading(72, c: ReadingConfidence.medium)));
    await tester.pumpAndSettle();
    expect(find.text('Medium confidence'), findsOneWidget);
    expect(find.text('Use this reading'), findsOneWidget);

    await tester.tap(find.text('Use this reading'));
    await tester.pumpAndSettle();
    expect(result?.value, 72);
    expect(disclaim, findsNothing); // dialog closed
    await controller.close();
  });

  testWidgets('low confidence requires the explicit "Accept anyway" gate',
      (tester) async {
    final controller = StreamController<MeasurementEvent>.broadcast();
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    controller.add(MeasurementSuccess(
        reading(61, c: ReadingConfidence.low, note: 'some movement')));
    await tester.pumpAndSettle();

    expect(find.text('Low confidence'), findsOneWidget);
    expect(find.text('Accept anyway'), findsOneWidget);
    expect(find.text('Use this reading'), findsNothing);
    expect(find.text('some movement'), findsOneWidget);
    await controller.close();
  });

  testWidgets('insufficient-signal offers retry and a manual-entry path',
      (tester) async {
    var runs = 0;
    late StreamController<MeasurementEvent> controller;
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () {
        runs++;
        controller = StreamController<MeasurementEvent>.broadcast();
        return controller.stream;
      },
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    controller
        .add(const MeasurementInsufficient('Too much movement detected'));
    await tester.pumpAndSettle();
    expect(find.text('Too much movement detected'), findsOneWidget);
    expect(find.text('Enter manually instead'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(runs, 2);
    expect(find.textContaining('remaining'), findsOneWidget);
    await controller.close();
  });

  testWidgets('permission denial fails closed with guidance, manual path kept',
      (tester) async {
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => false,
      run: () => const Stream<MeasurementEvent>.empty(),
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Could not start measuring'), findsOneWidget);
    expect(find.textContaining('camera permission'), findsOneWidget);
    expect(find.text('Enter manually instead'), findsOneWidget);
  });

  testWidgets('positioning (no timer) precedes the countdown for heart rate',
      (tester) async {
    final controller = StreamController<MeasurementEvent>.broadcast();
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
      positionsFirst: true,
      beginPositioning: () async {},
      endPositioning: () async {},
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Start measuring'), findsOneWidget);
    expect(find.text('Starting camera…'), findsOneWidget); // live preview slot
    expect(find.textContaining('remaining'), findsNothing); // timer NOT running

    await tester.tap(find.text('Start measuring'));
    await tester.pumpAndSettle();
    expect(find.textContaining('remaining'), findsOneWidget); // countdown on now
    await controller.close();
  });

  testWidgets('diagnostics show live while measuring and survive until retry',
      (tester) async {
    final controller = StreamController<MeasurementEvent>.broadcast();
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
    );
    await tester.pumpWidget(appWith(session: session));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    controller.add(const MeasurementProgress(
      2,
      debug: {'bpm': '98', 'torch': 'on', 'corr': '0.90'},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sensor diagnostics'), findsOneWidget);
    expect(find.text('bpm: 98'), findsOneWidget);
    expect(find.text('torch: on'), findsOneWidget);

    // Terminal insufficient keeps the diagnostics (collapsed by default).
    controller.add(const MeasurementInsufficient(
      'no reliable pulse',
      debug: {'bpm': '—', 'torch': 'OFF', 'corr': '0.02'},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sensor diagnostics'), findsOneWidget);
    expect(find.text('bpm: —'), findsNothing); // collapsed
    await tester.tap(find.text('Sensor diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('bpm: —'), findsOneWidget);
    expect(find.text('torch: OFF'), findsOneWidget);

    await controller.close();
  });
}
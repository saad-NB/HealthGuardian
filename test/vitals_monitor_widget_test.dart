import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/state/app_state.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';
import 'package:healthguardian/vitals/measurement_session.dart';
import 'package:healthguardian/vitals/models.dart';
import 'package:healthguardian/vitals/monitor/monitor_screen.dart';
import 'package:healthguardian/vitals/monitor/monitor_store.dart';

/// In-memory [MonitorStore] so widget tests stay in FakeAsync (real file IO
/// would never complete under the fake clock).
class _MemoryStore extends MonitorStore {
  _MemoryStore() : super();

  final List<VitalReading> _readings = [];

  @override
  Future<List<VitalReading>> loadRecent() async =>
      List<VitalReading>.unmodifiable(_readings);

  @override
  Future<void> save(VitalReading reading) async {
    _readings.removeWhere(
      (r) => r.kind == reading.kind && r.measuredAt == reading.measuredAt,
    );
    _readings.insert(0, reading);
    _readings.take(50).toList(growable: false);
  }

  @override
  Future<void> remove(VitalReading reading) async {
    _readings.removeWhere(
      (r) => r.kind == reading.kind && r.measuredAt == reading.measuredAt,
    );
  }

  @override
  Future<void> clear() async => _readings.clear();
}

void main() {
  VitalReading hr(double v,
          {ReadingConfidence c = ReadingConfidence.high}) =>
      VitalReading(
        kind: VitalKind.heartRate,
        value: v,
        confidence: c,
        measuredAt: DateTime(2026, 9, 12, 10),
      );

  Widget app({required MonitorStore store, MeasurementSession? session}) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: MonitorScreen(
        app: AppState(),
        store: store,
        sessionFor: (kind) =>
            kind == VitalKind.heartRate ? session : null,
      ),
    );
  }

  testWidgets('empty store shows the placeholder', (tester) async {
    await tester.pumpWidget(app(store: _MemoryStore()));
    await tester.pumpAndSettle();
    expect(find.text('Readings you accept will appear here.'), findsOneWidget);
  });

  testWidgets('stored readings render newest first', (tester) async {
    final store = _MemoryStore();
    await store.save(hr(78, c: ReadingConfidence.medium));
    await store.save(
      VitalReading(
        kind: VitalKind.breathingRate,
        value: 14,
        confidence: ReadingConfidence.high,
        measuredAt: DateTime(2026, 9, 12, 11),
      ),
    );
    await tester.pumpWidget(app(store: store));
    await tester.pumpAndSettle();

    expect(find.textContaining('Breathing rate — 14'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.textContaining('Heart rate — 78'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
  });

  testWidgets('stored readings show date and time', (tester) async {
    final store = _MemoryStore();
    await store.save(
      VitalReading(
        kind: VitalKind.heartRate,
        value: 76,
        confidence: ReadingConfidence.medium,
        measuredAt: DateTime(2026, 9, 12, 9, 5),
      ),
    );
    await tester.pumpWidget(app(store: store));
    await tester.pumpAndSettle();

    expect(find.textContaining('12 Sep 2026'), findsOneWidget);
    expect(find.textContaining('09:05'), findsOneWidget);
  });

  testWidgets('delete button removes the reading from the store',
      (tester) async {
    final store = _MemoryStore();
    await store.save(hr(78));
    await tester.pumpWidget(app(store: store));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('Heart rate — 78'), findsNothing);
    expect(find.text('Readings you accept will appear here.'), findsOneWidget);
    expect(await store.loadRecent(), isEmpty);
  });

  testWidgets('accepting a measurement persists it to the store',
      (tester) async {
    final store = _MemoryStore();
    final controller = StreamController<MeasurementEvent>.broadcast();
    final session = MeasurementSession(
      kind: VitalKind.heartRate,
      ensureAccess: (_) async => true,
      run: () => controller.stream,
    );
    await tester.pumpWidget(app(store: store, session: session));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Measure').first);
    await tester.pumpAndSettle();

    controller.add(MeasurementSuccess(hr(72, c: ReadingConfidence.high)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this reading'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Heart rate — 72'), findsOneWidget);
    final loaded = await store.loadRecent();
    expect(loaded.single.kind, VitalKind.heartRate);
    expect(loaded.single.value, closeTo(72, 1e-9));
    await controller.close();
  });
}
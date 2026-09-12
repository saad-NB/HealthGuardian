import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/vitals/models.dart';
import 'package:healthguardian/vitals/monitor/monitor_store.dart';

Directory _tempDir() => Directory.systemTemp.createTempSync('monitor_store');

VitalReading _reading(
  VitalKind kind, {
  double value = 78,
  ReadingConfidence confidence = ReadingConfidence.high,
  DateTime? at,
}) =>
    VitalReading(
      kind: kind,
      value: value,
      confidence: confidence,
      measuredAt: at ?? DateTime(2026, 9, 12, 10, 30),
    );

void main() {
  test('save then load returns newest-first (round-trip)', () async {
    final store = MonitorStore(file: File('${_tempDir().path}/readings.json'));
    final older = _reading(VitalKind.heartRate, at: DateTime(2026, 9, 12, 10));
    final newer = _reading(
      VitalKind.breathingRate,
      value: 14,
      at: DateTime(2026, 9, 12, 11),
    );

    await store.save(older);
    await store.save(newer);

    final loaded = await store.loadRecent();
    expect(loaded, hasLength(2));
    expect(loaded.first.kind, VitalKind.breathingRate);
    expect(loaded.first.value, closeTo(14, 1e-9));
    expect(loaded.first.confidence, ReadingConfidence.high);
    expect(loaded.first.measuredAt, DateTime(2026, 9, 12, 11));
  });

  test('empty or missing file loads as empty (legacy state tolerated)', () async {
    final store = MonitorStore(
      file: File('${_tempDir().path}/does_not_exist.json'),
    );
    expect(await store.loadRecent(), isEmpty);

    await store.save(_reading(VitalKind.heartRate));
    await store.clear();
    expect(await store.loadRecent(), isEmpty);
  });

  test('identical (kind + timestamp) save does not duplicate', () async {
    final store = MonitorStore(file: File('${_tempDir().path}/readings.json'));
    final reading = _reading(VitalKind.heartRate);
    await store.save(reading);
    await store.save(reading);
    expect(await store.loadRecent(), hasLength(1));
  });

  test('corrupt file entries are skipped, healthy ones survive', () async {
    final file = File('${_tempDir().path}/readings.json');
    final good = _reading(VitalKind.heartRate);
    await file.writeAsString(
      jsonEncode([
        {'garbage': true},
        "not a map",
        good.toJson(),
      ]),
    );
    final store = MonitorStore(file: file);
    final loaded = await store.loadRecent();
    expect(loaded, hasLength(1));
    expect(loaded.single.kind, VitalKind.heartRate);
  });

  test('remove deletes only the matching kind + timestamp', () async {
    final store = MonitorStore(file: File('${_tempDir().path}/readings.json'));
    final hrReading = _reading(VitalKind.heartRate);
    final rrReading = _reading(VitalKind.breathingRate, value: 14);
    await store.save(hrReading);
    await store.save(rrReading);
    expect(await store.loadRecent(), hasLength(2));

    await store.remove(hrReading);
    final loaded = await store.loadRecent();
    expect(loaded, hasLength(1));
    expect(loaded.single.kind, VitalKind.breathingRate);

    await store.remove(hrReading);
    expect(await store.loadRecent(), hasLength(1));
  });

  test('save caps the list at 50 newest-first', () async {
    final store = MonitorStore(file: File('${_tempDir().path}/readings.json'));
    var t = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 60; i++) {
      await store.save(
        _reading(
          i.isEven ? VitalKind.heartRate : VitalKind.breathingRate,
          value: i.toDouble(),
          at: t,
        ),
      );
      t = t.add(const Duration(minutes: 1));
    }
    final loaded = await store.loadRecent();
    expect(loaded, hasLength(50));
    expect(loaded.first.value, closeTo(59, 1e-9));
    expect(loaded.last.value, closeTo(10, 1e-9));
  });
}
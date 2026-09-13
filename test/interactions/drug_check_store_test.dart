import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/interactions/drug_check_store.dart';
import 'package:healthguardian/interactions/models.dart';

Directory _tempDir() => Directory.systemTemp.createTempSync('drug_check_store');

SavedDrugCheck _check(
  List<String> drugs, {
  List<DrugInteraction> interactions = const [],
  DateTime? at,
}) =>
    SavedDrugCheck(
      drugs: drugs,
      checkedAt: at ?? DateTime(2026, 9, 12, 10, 30),
      interactions: interactions,
    );

void main() {
  test('save then load returns newest-first (round-trip)', () async {
    final store = DrugCheckStore(file: File('${_tempDir().path}/checks.json'));
    await store.save(_check(['Warfarin', 'Aspirin'], at: DateTime(2026, 9, 12, 10)));
    await store.save(
      _check(
        ['Simvastatin', 'Amiodarone'],
        interactions: const [
          DrugInteraction(
            drugA: 'Simvastatin',
            drugB: 'Amiodarone',
            severity: InteractionSeverity.contraindicated,
          ),
        ],
        at: DateTime(2026, 9, 12, 11),
      ),
    );

    final loaded = await store.loadRecent();
    expect(loaded, hasLength(2));
    expect(loaded.first.drugs, ['Simvastatin', 'Amiodarone']);
    expect(loaded.first.interactions.single.severity,
        InteractionSeverity.contraindicated);
    expect(loaded.last.drugs, ['Warfarin', 'Aspirin']);
  });

  test('empty or missing file loads as empty', () async {
    final store = DrugCheckStore(file: File('${_tempDir().path}/none.json'));
    expect(await store.loadRecent(), isEmpty);
    await store.save(_check(['A', 'B']));
    await store.clear();
    expect(await store.loadRecent(), isEmpty);
  });

  test('identical names + timestamp do not duplicate', () async {
    final store = DrugCheckStore(file: File('${_tempDir().path}/checks.json'));
    final check = _check(['Warfarin', 'Aspirin']);
    await store.save(check);
    await store.save(check);
    expect(await store.loadRecent(), hasLength(1));
  });

  test('corrupt entries are skipped, healthy ones survive', () async {
    final file = File('${_tempDir().path}/checks.json');
    final good = _check(['Warfarin', 'Aspirin']);
    await file.writeAsString(
      jsonEncode([
        {'garbage': true},
        'not a map',
        good.toJson(),
      ]),
    );
    final loaded = await DrugCheckStore(file: file).loadRecent();
    expect(loaded, hasLength(1));
    expect(loaded.single.drugs, ['Warfarin', 'Aspirin']);
  });

  test('remove deletes only the matching check', () async {
    final store = DrugCheckStore(file: File('${_tempDir().path}/checks.json'));
    final a = _check(['A', 'B'], at: DateTime(2026, 1, 1));
    final b = _check(['C', 'D'], at: DateTime(2026, 1, 2));
    await store.save(a);
    await store.save(b);
    await store.remove(a);
    final loaded = await store.loadRecent();
    expect(loaded, hasLength(1));
    expect(loaded.single.drugs, ['C', 'D']);
  });

  test('save caps the list at 20 newest-first', () async {
    final store = DrugCheckStore(file: File('${_tempDir().path}/checks.json'));
    var t = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 25; i++) {
      await store.save(_check(['Drug$i', 'Other$i'], at: t));
      t = t.add(const Duration(minutes: 1));
    }
    final loaded = await store.loadRecent();
    expect(loaded, hasLength(20));
    expect(loaded.first.drugs, ['Drug24', 'Other24']);
  });
}

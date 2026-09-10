import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/record.dart';
import 'package:healthguardian/triage/record_store.dart';
import 'package:healthguardian/ui/screens/history_screen.dart';
import 'package:healthguardian/ui/screens/triage/triage_flow_screen.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';

/// In-memory [TriageRecordStore] so widget tests never touch the platform
/// keystore. Mirrors the real store's key layout exactly.
class FakeRecordStore extends TriageRecordStore {
  final Map<String, String> _data = {};
  String? _indexRaw;

  @override
  Future<List<TriageRecord>> loadAll() async {
    if (_indexRaw == null) return const [];
    final ids = (jsonDecode(_indexRaw!) as List).cast<String>();
    final out = <TriageRecord>[];
    for (final id in ids) {
      final payload = _data['triage_record_$id'];
      if (payload == null) continue;
      out.add(
        TriageRecord.fromJson(jsonDecode(payload) as Map<String, dynamic>),
      );
    }
    return out;
  }

  @override
  Future<void> save(TriageRecord record) async {
    _data['triage_record_${record.triageId}'] = jsonEncode(record.toJson());
    final ids = _indexRaw == null
        ? <String>[]
        : (jsonDecode(_indexRaw!) as List).cast<String>();
    _indexRaw = jsonEncode(
      [record.triageId, ...ids.where((id) => id != record.triageId)],
    );
  }

  @override
  Future<void> delete(String triageId) async {
    _data.remove('triage_record_$triageId');
    if (_indexRaw == null) return;
    final ids = (jsonDecode(_indexRaw!) as List)
        .cast<String>()
        .where((id) => id != triageId)
        .toList(growable: false);
    _indexRaw = jsonEncode(ids);
  }
}

TriageRecord _record(String id, TriageTier tier) => TriageRecord(
      version: '2.0',
      triageId: id,
      timestamp: DateTime(2026, 9, 7, 10, 30),
      finalTier: tier,
      inputs: <String, Object?>{'ageGroup': 'adult'},
      mergeReasons: const ['New stroke-like symptoms'],
      contributingScores: const {
        'vital': <String, dynamic>{
          'scale': 'news2',
          'score': 0,
          'tier': 'p5',
        },
      },
      missingParams: const [],
      substitutionApplied: false,
      safetyFlags: const [],
      modifiers: const {},
      gates: const {'triggered': []},
    );

void main() {
  group('TriageRecordStore', () {
    test('save + loadAll round-trips newest-first', () async {
      final store = FakeRecordStore();
      await store.save(_record('tg-1', TriageTier.p2));
      await store.save(_record('tg-2', TriageTier.p5));

      final records = await store.loadAll();
      expect(records, hasLength(2));
      expect(records.first.triageId, 'tg-2');
      expect(records.first.finalTier, TriageTier.p5);
      expect(records.last.triageId, 'tg-1');
    });

    test('save is idempotent by triageId', () async {
      final store = FakeRecordStore();
      await store.save(_record('tg-1', TriageTier.p3));
      await store.save(_record('tg-1', TriageTier.p1));
      final records = await store.loadAll();
      expect(records, hasLength(1));
      expect(records.single.finalTier, TriageTier.p1);
    });

    test('delete removes a record and its index entry', () async {
      final store = FakeRecordStore();
      await store.save(_record('tg-1', TriageTier.p2));
      await store.save(_record('tg-2', TriageTier.p4));
      await store.delete('tg-1');
      final records = await store.loadAll();
      expect(records, hasLength(1));
      expect(records.single.triageId, 'tg-2');
    });
  });

  group('History screen', () {
    testWidgets('lists records newest first with tier badge', (tester) async {
      final store = FakeRecordStore();
      await store.save(_record('tg-1', TriageTier.p2));
      await store.save(_record('tg-2', TriageTier.p5));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HistoryScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Triage history'), findsOneWidget);
      expect(find.textContaining('P5 - Minor'), findsOneWidget);
      expect(find.textContaining('P2 - Very Urgent'), findsOneWidget);
    });

    testWidgets('empty state shows placeholder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HistoryScreen(store: FakeRecordStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No triage records yet'), findsOneWidget);
    });

    testWidgets('delete removes the record from the list', (tester) async {
      final store = FakeRecordStore();
      await store.save(_record('tg-1', TriageTier.p4));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HistoryScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('P4 - Standard'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('No triage records yet'), findsOneWidget);
    });
  });

  group('Save-on-result', () {
    testWidgets('landing on result persists a record to the store',
        (tester) async {
      final store = FakeRecordStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: TriageFlowScreen(store: store),
        ),
      );

      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      Future<void> cont() async {
        await tester.ensureVisible(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      await tap('Adult');
      await cont(); // patient info -> danger gates
      for (var i = 0; i < 9; i++) {
        await cont(); // danger gates + 8 NEWS2 vitals
      }
      await tap('Other problem');
      await cont(); // complaint menu -> any other problems
      await tap('No, that is all');
      await cont(); // modifiers

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      final records = await store.loadAll();
      expect(records, hasLength(1));
      expect(records.single.finalTier, TriageTier.p5);
      expect(records.single.inputs['age'], 'adult');
      final vital = records.single.contributingScores['vital'] as Map;
      expect(vital['scale'], 'news2');
    });
  });
}
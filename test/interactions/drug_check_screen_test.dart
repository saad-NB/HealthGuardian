import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/interactions/dataset.dart';
import 'package:healthguardian/interactions/drug_check_screen.dart';
import 'package:healthguardian/interactions/drug_check_store.dart';
import 'package:healthguardian/state/app_state.dart';

/// In-memory [DrugCheckStore] so widget tests stay in FakeAsync (real file IO
/// would never complete under the fake clock).
class _MemoryStore extends DrugCheckStore {
  final List<SavedDrugCheck> _checks = [];

  @override
  Future<List<SavedDrugCheck>> loadRecent() async =>
      List<SavedDrugCheck>.unmodifiable(_checks);

  @override
  Future<void> save(SavedDrugCheck check) async => _checks.insert(0, check);

  @override
  Future<void> remove(SavedDrugCheck check) async =>
      _checks.removeWhere((c) => c.checkedAt == check.checkedAt);

  @override
  Future<void> clear() async => _checks.clear();
}

InteractionDataset _dataset() => InteractionDataset.fromJson(
      {
        'pairs': [
          ['Warfarin', 'Aspirin', 0],
          ['Simvastatin', 'Amiodarone', 3],
        ],
      },
      {
        'names': [
          ['Warfarin', '11289'],
          ['Aspirin', '1191'],
          ['Simvastatin', '36567'],
          ['Amiodarone', '703'],
        ],
      },
    );

Widget _screen(
  DrugCheckStore store, {
  void Function(String title, String context)? onAskAi,
}) =>
    MaterialApp(
      home: DrugCheckScreen(
        app: AppState(),
        dataset: _dataset(),
        store: store,
        onAskAi: onAskAi,
      ),
    );

Future<void> _addDrug(
  WidgetTester tester,
  String typed,
  String suggestion,
) async {
  await tester.enterText(find.byType(TextField), typed);
  await tester.pump();
  await tester.tap(find.text(suggestion).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => EditableText.debugDeterministicCursor = true);
  tearDown(() => EditableText.debugDeterministicCursor = false);

  testWidgets('adds medicines, checks, and lists the interaction',
      (tester) async {
    await tester.pumpWidget(_screen(_MemoryStore()));
    await tester.pumpAndSettle();

    await _addDrug(tester, 'warfarin', 'Warfarin');
    await _addDrug(tester, 'aspirin', 'Aspirin');

    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    expect(find.text('Interaction on record'), findsOneWidget);
    expect(find.text('Warfarin + Aspirin'), findsWidgets);
  });

  testWidgets('contraindicated pair shows a blocking dialog', (tester) async {
    await tester.pumpWidget(_screen(_MemoryStore()));
    await tester.pumpAndSettle();

    await _addDrug(tester, 'simvastatin', 'Simvastatin');
    await _addDrug(tester, 'amiodarone', 'Amiodarone');

    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    expect(find.text('Serious interaction'), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.text('Serious interaction'), findsNothing);
  });

  testWidgets('reports when no interaction is found', (tester) async {
    await tester.pumpWidget(_screen(_MemoryStore()));
    await tester.pumpAndSettle();

    await _addDrug(tester, 'warfarin', 'Warfarin');
    await _addDrug(tester, 'simvastatin', 'Simvastatin');

    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No known interactions'), findsOneWidget);
  });

  testWidgets('flags medicines missing from the reference data', (tester) async {
    await tester.pumpWidget(_screen(_MemoryStore()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Unobtainium');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await _addDrug(tester, 'warfarin', 'Warfarin');

    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not recognised'), findsOneWidget);
  });

  testWidgets('Ask AI hands off the combination as context', (tester) async {
    String? capturedTitle;
    String? capturedContext;
    await tester.pumpWidget(
      _screen(
        _MemoryStore(),
        onAskAi: (title, context) {
          capturedTitle = title;
          capturedContext = context;
        },
      ),
    );
    await tester.pumpAndSettle();

    await _addDrug(tester, 'warfarin', 'Warfarin');
    await _addDrug(tester, 'aspirin', 'Aspirin');
    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    final askAi = find.text('Ask AI about these medicines');
    await tester.ensureVisible(askAi);
    await tester.pumpAndSettle();
    await tester.tap(askAi);
    await tester.pumpAndSettle();

    expect(capturedTitle, contains('Warfarin'));
    expect(capturedTitle, contains('Aspirin'));
    expect(capturedContext, contains('Warfarin'));
    expect(capturedContext, contains('Aspirin'));
    expect(capturedContext, contains('Reported'));
  });

  testWidgets('Explain without the model shows a download hint', (tester) async {    await tester.pumpWidget(_screen(_MemoryStore()));
    await tester.pumpAndSettle();

    await _addDrug(tester, 'warfarin', 'Warfarin');
    await _addDrug(tester, 'aspirin', 'Aspirin');
    await tester.tap(find.text('Check interactions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Explain').first);
    await tester.pump();

    expect(
      find.textContaining('Download the MedGemma model'),
      findsOneWidget,
    );
  });
}

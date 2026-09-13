import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/interactions/dataset.dart';
import 'package:healthguardian/interactions/engine.dart';
import 'package:healthguardian/interactions/models.dart';

InteractionEngine _engine() => InteractionEngine(
      InteractionDataset.fromJson(
        {
          'pairs': [
            ['Warfarin', 'Aspirin', 0],
            ['Simvastatin', 'Amiodarone', 3],
            ['Warfarin', 'Amiodarone', 2],
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
      ),
    );

void main() {
  group('InteractionEngine.check', () {
    test('returns all matched pairs, most urgent first', () {
      final results = _engine().check(['Warfarin', 'Aspirin', 'Amiodarone', 'Simvastatin']);
      expect(results, hasLength(3));
      expect(results.first.severity, InteractionSeverity.contraindicated);
      expect(results[1].severity, InteractionSeverity.severe);
      expect(results.last.severity, InteractionSeverity.reported);
    });

    test('collapses duplicate medicines (case/space insensitive)', () {
      final results = _engine().check(['Warfarin', 'warfarin', 'Aspirin']);
      expect(results, hasLength(1));
      expect(results.single.drugA.toLowerCase(), 'warfarin');
    });

    test('no interactions yields an empty list', () {
      expect(_engine().check(['Warfarin', 'Simvastatin']), isEmpty);
      expect(_engine().check(['Warfarin']), isEmpty);
      expect(_engine().check(const []), isEmpty);
    });

    test('hasBlocking is true for severe/contraindicated only', () {
      final engine = _engine();
      expect(
        engine.hasBlocking(engine.check(['Simvastatin', 'Amiodarone'])),
        isTrue,
      );
      expect(engine.hasBlocking(engine.check(['Warfarin', 'Aspirin'])), isFalse);
    });
  });

  group('InteractionEngine.unknownDrugs', () {
    test('lists only names missing from the dataset, in input order', () {
      final unknown = _engine().unknownDrugs(
        ['Warfarin', 'Unobtainium', 'Aspirin', 'Vibranium'],
      );
      expect(unknown, ['Unobtainium', 'Vibranium']);
    });

    test('ignores blanks and duplicates', () {
      final unknown = _engine().unknownDrugs(['', '  ', 'X', 'x']);
      expect(unknown, ['X']);
    });
  });
}

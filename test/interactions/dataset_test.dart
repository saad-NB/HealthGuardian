import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/interactions/dataset.dart';
import 'package:healthguardian/interactions/models.dart';

InteractionDataset _fixture() => InteractionDataset.fromJson(
      {
        'severity': ['reported', 'moderate', 'severe', 'contraindicated'],
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
          ['Sodium Phosphate', ''],
        ],
      },
    );

void main() {
  group('normalizeDrugName', () {
    test('lowercases, strips punctuation and collapses spaces', () {
      expect(normalizeDrugName('  Sodium  Phosphate '), 'sodium phosphate');
      expect(normalizeDrugName('N,N-Dimethyl'), 'n n dimethyl');
      expect(normalizeDrugName(''), '');
    });
  });

  group('InteractionDataset', () {
    test('severityFor is symmetric and input-tolerant', () {
      final ds = _fixture();
      expect(ds.severityFor('Warfarin', 'Aspirin'), InteractionSeverity.reported);
      expect(ds.severityFor('aspirin', 'WARFARIN'), InteractionSeverity.reported);
      expect(
        ds.severityFor('Simvastatin', 'Amiodarone'),
        InteractionSeverity.contraindicated,
      );
    });

    test('unknown pair returns null', () {
      final ds = _fixture();
      expect(ds.severityFor('Warfarin', 'Amiodarone'), isNull);
      expect(ds.severityFor('Warfarin', 'Warfarin'), isNull);
    });

    test('isKnownDrug tolerates spacing and punctuation', () {
      final ds = _fixture();
      expect(ds.isKnownDrug('warfarin'), isTrue);
      expect(ds.isKnownDrug('Sodium  Phosphate'), isTrue);
      expect(ds.isKnownDrug('Unobtainium'), isFalse);
    });

    test('counts reflect the fixture', () {
      final ds = _fixture();
      expect(ds.drugCount, 5);
      expect(ds.pairCount, 2);
    });

    test('search returns prefix matches before substring matches', () {
      final ds = _fixture();
      final hits = ds.search('a');
      expect(hits, isNotEmpty);
      expect(hits.first.name.toLowerCase().startsWith('a'), isTrue);
      expect(ds.search(''), isEmpty);
    });

    test('search respects the limit', () {
      final ds = _fixture();
      expect(ds.search('a', limit: 1), hasLength(1));
    });
  });

  group('bundled assets', () {
    test('parse and contain the expected scale', () {
      final ddi = jsonDecode(File('assets/data/ddi.json').readAsStringSync())
          as Map<String, dynamic>;
      final names =
          jsonDecode(File('assets/data/drug_names.json').readAsStringSync())
              as Map<String, dynamic>;
      final ds = InteractionDataset.fromJson(ddi, names);

      expect(ds.drugCount, greaterThan(1000));
      expect(ds.pairCount, greaterThan(10000));
      expect(
        ds.severityFor('Warfarin', 'Aspirin'),
        InteractionSeverity.moderate,
      );
      expect(
        ds.severityFor('Simvastatin', 'Amiodarone'),
        InteractionSeverity.contraindicated,
      );
    });
  });
}

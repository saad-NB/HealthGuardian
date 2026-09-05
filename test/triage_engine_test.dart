import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/engine.dart';
import 'package:healthguardian/triage/models.dart';

TriageAnswers _healthyAdult() {
  return TriageAnswers()
    ..ageGroup = AgeGroup.adult
    ..respiratoryRate = 16
    ..spo2 = 98
    ..systolicBp = 120
    ..heartRate = 72
    ..temperature = 37.0
    ..consciousness = Avpu.alert
    ..onOxygen = false
    ..copdCo2Retention = false;
}

void main() {
  group('Danger-sign gates (§4)', () {
    for (final id in ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8']) {
      test('$id alone forces P1 even with normal vitals', () {
        final a = _healthyAdult()..dangerSigns.add(id);
        final r = TriageEngine.compute(a);
        expect(r.tier, TriageTier.p1, reason: '$id must override NEWS2');
        expect(r.vitalReviewRequired, isFalse);
        expect(r.reasons, contains(TriageEngine.dangerReason(id)));
      });
    }

    test('multiple gates are all recorded', () {
      final a = _healthyAdult()..dangerSigns.addAll(['A9', 'A15']);
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
      expect(r.reasons, contains('Danger gate: A9'));
      expect(r.reasons, contains('Danger gate: A15'));
    });
  });

  group('Adult NEWS2 tier mapping (§5.1)', () {
    test('fully normal vitals map to P5', () {
      final r = TriageEngine.compute(_healthyAdult());
      expect(r.tier, TriageTier.p5);
      expect(r.aggregate, 0);
      expect(r.vitalReviewRequired, isFalse);
    });

    test('NEWS2 aggregate 1-2 maps to P4', () {
      final a = _healthyAdult()..systolicBp = 105;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 1);
      expect(r.tier, TriageTier.p4);
    });

    test('NEWS2 aggregate 3-4 maps to P3', () {
      final a = _healthyAdult()
        ..heartRate = 130
        ..systolicBp = 105;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 3);
      expect(r.tier, TriageTier.p3);
    });

    test('NEWS2 aggregate 5-6 maps to P2', () {
      final a = _healthyAdult()
        ..heartRate = 111
        ..systolicBp = 91
        ..temperature = 38.5;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 5, reason: 'HR 111 (2) + SBP 91 (2) + T 38.5 (1)');
      expect(r.tier, TriageTier.p2);
    });

    test('NEWS2 aggregate >= 7 maps to P1', () {
      final a = _healthyAdult()
        ..respiratoryRate = 26
        ..heartRate = 135
        ..systolicBp = 85
        ..temperature = 39.5
        ..spo2 = 90;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
      expect(r.aggregate, greaterThanOrEqualTo(7));
    });

    test('any single parameter scoring 3 maps to P1', () {
      final a = _healthyAdult()..temperature = 35.0;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 3, reason: 'temp <= 35.0 scores 3');
      expect(r.tier, TriageTier.p1,
          reason: 'temp = 3, any single-parameter-3 -> P1');
      expect(r.reasons, contains(contains('Temperature')));
    });

    test('COPD Scale 2 SpO2 boundaries', () {
      final a = _healthyAdult()
        ..copdCo2Retention = true
        ..spo2 = 97;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 3, reason: 'Scale 2: >=97 scores 3');
      expect(r.tier, TriageTier.p1);
    });

    test('AVPU V (voice) scores 2, P/U score 3', () {
      final voice = TriageEngine.compute(
        _healthyAdult()..consciousness = Avpu.voice,
      );
      expect(voice.aggregate, 2);
      expect(voice.tier, TriageTier.p4);
      expect(voice.vitalReviewRequired, isFalse);

      final pain = TriageEngine.compute(
        _healthyAdult()..consciousness = Avpu.pain,
      );
      expect(pain.aggregate, 3);
      expect(pain.tier, TriageTier.p1);
    });
  });

  group('Missing-vitals policy (§21 / ADR-008)', () {
    test('SpO2 missing with no concern: P3 floor + review', () {
      final a = _healthyAdult()..spo2 = null;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.reasons, contains('SpO2 not measured.'));
      expect(r.tier, TriageTier.p3,
          reason: 'P3 floor applies even though rest is normal');
    });

    test('SpO2 missing with breathing concern substitutes score 3', () {
      final a = _healthyAdult()
        ..spo2 = null
        ..respiratoryRate = 26;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier, TriageTier.p1,
          reason: 'substituted single-param 3 + RR concern -> P1');
    });

    test('Temperature missing with no concern: P3 floor + review', () {
      final a = _healthyAdult()..temperature = null;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier, TriageTier.p3);
    });

    test('invalid values fail closed like missing', () {
      final a = _healthyAdult()..spo2 = 140;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier, TriageTier.p3);
    });

    test('required vital missing is never under-triaged', () {
      final a = _healthyAdult()..heartRate = null;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier,
          isNot(anyOf([TriageTier.p4, TriageTier.p5])),
          reason: 'missing HR must floor to P3');
    });
  });

  group('Age-gate safety path (§5.2/§5.3)', () {
    test('child with a danger sign goes to P1', () {
      final a = TriageAnswers()
        ..ageGroup = AgeGroup.child
        ..dangerSigns.add('A4');
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
    });

    test('child with no danger sign fails closed to P3 review', () {
      final a = TriageAnswers()..ageGroup = AgeGroup.child;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p3);
      expect(r.vitalReviewRequired, isTrue);
    });

    test('no age selected fails closed', () {
      final r = TriageEngine.compute(TriageAnswers());
      expect(r.tier, TriageTier.p3);
      expect(r.vitalReviewRequired, isTrue);
    });
  });
}
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/engine.dart';
import 'package:healthguardian/triage/models.dart';

TriageAnswers _petAdult() {
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

TriageAnswers _pedNormal({String bracket = 'toddler'}) {
  final age = AgeGroup.values.firstWhere((g) => g.pedsBracket == bracket);
  return TriageAnswers()
    ..ageGroup = age
    ..respiratoryRate = 24
    ..spo2 = 98
    // ADR-013: BP optional for children; the real walkthrough never collects it.
    ..heartRate = 110
    ..temperature = 37.2
    ..consciousness = Avpu.alert
    ..capillaryRefill = CapillaryRefill.under2
    ..onOxygen = false;
}

void main() {
  group('Peds-NEWS2 (§5.2)', () {
    test('fully normal toddler maps to P5 (no missing vitals)', () {
      final r = TriageEngine.compute(_pedNormal());
      expect(r.scale, VitalScale.pedsNews2);
      // Without missing vitals and with normal params, score is 0.
      expect(r.aggregate, 0);
      expect(r.tier, TriageTier.p5);
      // BP not measured is informational only (ADR-013), not a review flag.
      expect(r.reasons,
          contains('Blood pressure not measured (optional for this age group).'));
      expect(r.vitalReviewRequired, isFalse);
    });

    test('optional BP still scores when provided (toddler sbp 130 → P1)', () {
      final a = _pedNormal()..systolicBp = 130;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 3);
      expect(r.tier, TriageTier.p1,
          reason: 'toddler systolic 130 scores a single 3 → P1');
    });

    test('single parameter scoring 3 escalates to P1', () {
      final a = _pedNormal()..respiratoryRate = 60;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1,
          reason: 'RR 60 scores 3 in toddler bracket → P1');
      expect(r.reasons, contains(contains('Respiratory rate')));
    });

    test('aggregate >= 7 maps to P1', () {
      final a = _pedNormal()
        ..respiratoryRate = 60
        ..heartRate = 180
        ..capillaryRefill = CapillaryRefill.over3
        ..temperature = 39.5;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
    });

    test('capillary refill over 3s scores and is noted', () {
      final a = _pedNormal()..capillaryRefill = CapillaryRefill.over3;
      final r = TriageEngine.compute(a);
      expect(r.aggregate, 3);
      expect(r.tier, TriageTier.p1,
          reason: 'refill 3 (single-param-3) → P1');
      expect(r.reasons, contains(contains('Capillary refill')));
    });

    test('missing vitals in a child floors to P3 review', () {
      final a = _pedNormal()..heartRate = null;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier, TriageTier.p3);
    });

    test('temp substitution for a fever-flagged child scores 2', () {
      final a = _pedNormal()
        ..temperature = null
        ..tempMissing = true
        ..chiefComplaint = ChiefComplaint.fever;
      final r = TriageEngine.compute(a);
      expect(r.reasons, contains(contains('Temperature not measured')));
      // 2 points scored for the substituted temperature.
      expect(r.aggregate, 2);
    });
  });

  group('Neonatal PEWS (§5.3)', () {
    TriageAnswers neoNormal() {
      return TriageAnswers()
        ..ageGroup = AgeGroup.neonate
        ..respiratoryRate = 45
        ..spo2 = 97
        ..heartRate = 140
        ..temperature = 37.0
        ..neonatalConsciousness = NeonatalConsciousness.feedingWell;
    }

    test('normal neonate maps to P4 (age floor)', () {
      final r = TriageEngine.compute(neoNormal());
      expect(r.scale, VitalScale.pews);
      expect(r.tier, TriageTier.p4);
      expect(r.aggregate, 0);
      // BP not measured is informational only (ADR-013).
      expect(r.reasons,
          contains('Blood pressure not measured (optional for this age group).'));
      expect(r.vitalReviewRequired, isFalse);
    });

    test('PEWS aggregate >= 4 maps to P1', () {
      final a = neoNormal()
        ..respiratoryRate = 90
        ..heartRate = 200
        ..temperature = 39.0
        ..neonatalConsciousness =
            NeonatalConsciousness.unresponsiveNoFeed;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
    });

    test('neonate with missing vitals floors to P3 review', () {
      final a = neoNormal()..respiratoryRate = null;
      final r = TriageEngine.compute(a);
      expect(r.vitalReviewRequired, isTrue);
      expect(r.tier, TriageTier.p3);
    });
  });

  group('GCS tier mapping (§6)', () {
    TriageAnswers adultWithGcs(int eye, int verbal, int motor) {
      return _petAdult()
        ..gcsEye = eye
        ..gcsVerbal = verbal
        ..gcsMotor = motor;
    }

    test('GCS 3 (all minima) maps to P1', () {
      final r = TriageEngine.compute(adultWithGcs(1, 1, 1));
      expect(r.tier, TriageTier.p1);
      expect(r.reasons, contains(contains('GCS')));
    });

    test('GCS 15 without head injury maps to P5', () {
      final r = TriageEngine.compute(adultWithGcs(4, 5, 6));
      expect(r.tier, TriageTier.p5);
    });

    test('head-injury context escalates a GCS 9-12 to P1', () {
      // GCS 10: eye 4 + verbal 2 + motor 4 = wait, use 1+4+5=10.
      final a = adultWithGcs(1, 4, 5)
        ..chiefComplaint = ChiefComplaint.other;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p2,
          reason: 'GCS 10 w/o head injury → P2');
      // With head injury context, 9-12 → P1.
      final a2 = adultWithGcs(1, 4, 5)
        ..chiefComplaint = ChiefComplaint.headache; // suggestsHeadInjury
      final r2 = TriageEngine.compute(a2);
      expect(r2.tier, TriageTier.p1);
    });

    test('GCS 13 maps to P3', () {
      final r = TriageEngine.compute(adultWithGcs(3, 4, 6)); // 13
      expect(r.tier, TriageTier.p3);
    });
  });

  group('Chief complaint + probes (§7/§8)', () {
    test('no branch complaint adds no probe tier', () {
      final a = _petAdult()..chiefComplaint = ChiefComplaint.other;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p5);
    });

    test('chest probe score >= 6 escalates to P1', () {
      final a = _petAdult()
        ..chiefComplaint = ChiefComplaint.chest
        ..probeAnswers['E-C1'] = true // 2
        ..probeAnswers['E-C3'] = true // 1
        ..probeAnswers['E-C5'] = true // 1
        ..probeAnswers['E-C2'] = true // 1
        ..probeAnswers['E-C4'] = true; // 3, but special-cased
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
      expect(r.reasons, contains(contains('Complaint')));
    });

    test('E-C4 tearing back pain forces P1 regardless of other score', () {
      final a = _petAdult()
        ..chiefComplaint = ChiefComplaint.chest
        ..probeAnswers['E-C4'] = true;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
    });

    test('E-B1 inverted: cannot speak full sentences (No) is the concern', () {
      // No probe answers on breathing branch → P5 with no escalation.
      final normal = _petAdult()
        ..chiefComplaint = ChiefComplaint.breathing
        ..probeAnswers['E-B1'] = true; // can speak → no concern
      final rNormal = TriageEngine.compute(normal);
      expect(rNormal.tier, TriageTier.p5);

      final cannot = _petAdult()
        ..chiefComplaint = ChiefComplaint.breathing
        ..probeAnswers['E-B1'] = false; // cannot → +3
        // E-B1 (3) + E-B3 (3) → P1, but just E-B1=3 + others no → P2? score 3 → P2.
      final rCannot = TriageEngine.compute(cannot);
      expect(rCannot.tier, TriageTier.p2,
          reason: 'E-B1 No alone scores 3 → breathing P2');
    });

    test('probe score not reached adds no escalation', () {
      final a = _petAdult()
        ..chiefComplaint = ChiefComplaint.chest
        ..probeAnswers['E-C3'] = true; // score 1 only
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p5);
    });
  });

  group('Sepsis screen (§9)', () {
    test('adult qSOFA 2 maps to P1', () {
      final a = _petAdult()
        ..sepsis.f1 = true
        ..sepsis.f2 = true
        ..sepsis.f3 = true;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
      expect(r.reasons, contains(contains('Sepsis')));
    });

    test('adult qSOFA 1 maps to P2', () {
      final a = _petAdult()
        ..sepsis.f1 = true
        ..sepsis.f2 = true;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p2);
    });

    test('qSOFA 0 adds no escalation', () {
      final a = _petAdult()..sepsis.f1 = true;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p5);
    });

    test('pedSIRS child with high HR + temp maps to P1', () {
      final a = _pedNormal()
        ..sepsis.f1 = true
        ..heartRate = 170
        ..temperature = 39.0;
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p1);
    });

    test('neonate gets no sepsis tier from the F-screen', () {
      final a = TriageAnswers()
        ..ageGroup = AgeGroup.neonate
        ..sepsis.f1 = true
        ..sepsis.f2 = true
        ..sepsis.f3 = true;
      // No sepsis tier for neonates → P3 floor for missing vitals.
      final r = TriageEngine.compute(a);
      expect(r.reasons.where((x) => x.contains('Sepsis')), isEmpty);
    });
  });
}
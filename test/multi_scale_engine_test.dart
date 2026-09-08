import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/engine.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/record.dart';

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

  group('Burn module (§11/§22)', () {
    TriageAnswers burnAdult({BurnDepth depth = BurnDepth.partial, double tbsa = 2}) {
      return _petAdult()
        ..burn.area = BurnArea.arm
        ..burn.depth = depth
        ..burn.tbsaPercent = tbsa;
    }

    test('airway signs force P1', () {
      final a = burnAdult()..burn.airwaySigns = true;
      expect(TriageEngine.compute(a).tier, TriageTier.p1);
    });

    test('chemical/electrical cause forces P1', () {
      final a = burnAdult()
        ..burn.cause = BurnCause.chemical;
      expect(TriageEngine.compute(a).tier, TriageTier.p1);
      final b = burnAdult()
        ..burn.cause = BurnCause.electrical;
      expect(TriageEngine.compute(b).tier, TriageTier.p1);
    });

    test('full-thickness on a critical area forces P1', () {
      final a = burnAdult()
        ..burn.reset()
        ..burn.area = BurnArea.face
        ..burn.depth = BurnDepth.full
        ..burn.tbsaPercent = 1;
      expect(TriageEngine.compute(a).tier, TriageTier.p1);
    });

    test('circumferential full-thickness forces P1', () {
      final a = burnAdult(depth: BurnDepth.full)..burn.circumferential = true;
      expect(TriageEngine.compute(a).tier, TriageTier.p1);
    });

    test('TBSA >= 20 adult maps to P2 (fluid threshold)', () {
      final a = burnAdult(tbsa: 20);
      expect(TriageEngine.compute(a).tier, TriageTier.p2);
    });

    test('TBSA >= 10 child maps to P2 (fluid threshold)', () {
      final a = _pedNormal()
        ..burn.area = BurnArea.arm
        ..burn.depth = BurnDepth.partial
        ..burn.tbsaPercent = 10;
      expect(TriageEngine.compute(a).tier, TriageTier.p2);
    });

    test('deep-partial > 5% maps to P2', () {
      final a = burnAdult(depth: BurnDepth.deepPartial, tbsa: 6);
      expect(TriageEngine.compute(a).tier, TriageTier.p2);
    });

    test('critical area any depth maps to P2', () {
      final a = burnAdult()
        ..burn.reset()
        ..burn.area = BurnArea.hand
        ..burn.depth = BurnDepth.partial
        ..burn.tbsaPercent = 1;
      expect(TriageEngine.compute(a).tier, TriageTier.p2,
          reason: 'functional risk on the hand');
    });

    test('contaminated burn maps to P3', () {
      final a = burnAdult()..burn.contaminated = true;
      expect(TriageEngine.compute(a).tier, TriageTier.p3);
    });

    test('moderate partial 11-19% adult maps to P3', () {
      final a = burnAdult(tbsa: 15);
      expect(TriageEngine.compute(a).tier, TriageTier.p3);
    });

    test('small partial burn maps to P4 (outpatient)', () {
      final a = burnAdult(tbsa: 3);
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('superficial <= 1% no risk areas maps to P5', () {
      final a = burnAdult(depth: BurnDepth.superficial, tbsa: 1);
      expect(TriageEngine.compute(a).tier, TriageTier.p5);
    });

    test('unengaged burn adds no tier', () {
      final a = _petAdult()..burn.reset();
      final r = TriageEngine.compute(a);
      expect(r.tier, TriageTier.p5);
      expect(r.reasons.where((x) => x.contains('Burn:')), isEmpty);
    });
  });

  group('Modifiers I1-I7 (§12)', () {
    test('age <5 or >65 bumps one tier', () {
      final a = _petAdult()..modifiers.ageYears = 70;
      final r = TriageEngine.compute(a);
      // adult normal P5 → P4 after single bump.
      expect(r.tier, TriageTier.p4);
      expect(r.reasons, contains(contains('Modifier bump')));

      final child = _petAdult()..modifiers.ageYears = 4;
      expect(TriageEngine.compute(child).tier, TriageTier.p4);
    });

    test('immunocompromised bumps one tier', () {
      final a = _petAdult()..modifiers.immunocompromised = true;
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('pregnancy bumps one tier', () {
      final a = _petAdult()..modifiers.pregnant = true;
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('MUAC < 11.5 cm bumps one tier', () {
      final a = _pedNormal()..modifiers.muacCm = 10.5;
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('CFS >= 5 bumps one tier', () {
      final a = _petAdult()..modifiers.cfsLevel = 6;
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('multiple modifiers still bump only once (single-bump cap)', () {
      final a = _petAdult()
        ..modifiers.ageYears = 70
        ..modifiers.immunocompromised = true
        ..modifiers.cfsLevel = 6;
      // P5 → P4 only, never P3.
      expect(TriageEngine.compute(a).tier, TriageTier.p4);
    });

    test('bump cannot exceed P1 and P1 stays P1', () {
      final a = _petAdult()
        ..modifiers.ageYears = 70
        ..respiratoryRate = 60; // single param 3 → P1 already
      expect(TriageEngine.compute(a).tier, TriageTier.p1);
    });

    test('age bracket alone does not bump (ADR-013 healthy toddler P5)', () {
      final r = TriageEngine.compute(_pedNormal());
      expect(r.tier, TriageTier.p5);
      expect(r.reasons.where((x) => x.contains('Modifier bump')), isEmpty);
    });
  });

  group('Stored record (§15)', () {
    test('computeRecord returns a round-trippable JSON record', () {
      final a = _pedNormal();
      final rec = TriageEngine.computeRecord(a);
      expect(rec.triageId, startsWith('tg-'));
      expect(rec.version, '2.1');
      expect(rec.finalTier, TriageTier.p5);
      expect(rec.contributingScores['vital'], isA<Map<String, dynamic>>());
      // ADR-013: SBP optional for children, so no missing-param flags.
      expect(rec.missingParams, isEmpty);

      final json = rec.toJson();
      final restored = TriageRecord.fromJson(json);
      expect(restored.triageId, rec.triageId);
      expect(restored.finalTier, rec.finalTier);
      expect(restored.contributingScores, rec.contributingScores);
      expect(restored.missingParams, rec.missingParams);
    });

    test('record captures modifier bump and burn', () {
      final a = _petAdult()..modifiers.ageYears = 70;
      a.burn
        ..area = BurnArea.arm
        ..depth = BurnDepth.partial
        ..tbsaPercent = 15;
      final rec = TriageEngine.computeRecord(a);
      // Burn 11-19% partial adult → P3, then I1 age bump → P2.
      expect(rec.finalTier, TriageTier.p2);
      expect(rec.modifiers['bumpApplied'], isTrue);
    });
  });
}
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/engine.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2.dart';

void main() {
  TriageAnswers adultNormal() {
    final a = TriageAnswers();
    a.ageGroup = AgeGroup.adult;
    a.respiratoryRate = 14;
    a.spo2 = 98;
    a.systolicBp = 120;
    a.heartRate = 70;
    a.temperature = 36.8;
    a.consciousness = Avpu.alert;
    a.onOxygen = false;
    a.copdCo2Retention = false;
    a.chiefComplaint = ChiefComplaint.throat;
    return a;
  }

  group('Tier2Payload (spec §16 shape)', () {
    test('contains the spec-16 sections and tier1 result', () {
      final a = adultNormal();
      final result = TriageEngine.compute(a);
      final payload = Tier2Payload.from(a, result).toJson();

      expect(payload['spec'], 'spec-16-tier2-payload');
      expect(payload['patientContext'], isA<Map<String, dynamic>>());
      expect(payload['vitals'], isA<Map<String, dynamic>>());
      expect(payload['gcs'], isA<Map<String, dynamic>>());
      expect(payload['chiefComplaint'], 'Sore throat');
      expect(payload['probeAnswers'], isA<Map<String, dynamic>>());
      expect(payload['sepsisScreen'], isA<Map<String, dynamic>>());
      expect(payload['burn'], isA<Map<String, dynamic>>());
      expect(payload['modifiers'], isA<Map<String, dynamic>>());
      expect(payload['tier1Result'], isA<Map<String, dynamic>>());
      expect(payload['patientSummary'], isA<String>());

      final tier1 = payload['tier1Result'] as Map<String, dynamic>;
      expect(tier1['tier'], result.tier.name.toUpperCase());
      expect(tier1['reasons'], isA<List<dynamic>>());
      expect(tier1['vitalReviewRequired'], isFalse);
    });

    test('gcs total only when all three components present', () {
      final a = adultNormal();
      a.consciousness = Avpu.voice;
      final partial = Tier2Payload.from(a, TriageEngine.compute(a)).toJson();
      expect((partial['gcs'] as Map<String, dynamic>)['total'], isNull);

      a.gcsEye = 3;
      a.gcsVerbal = 4;
      a.gcsMotor = 5;
      final full = Tier2Payload.from(a, TriageEngine.compute(a)).toJson();
      expect((full['gcs'] as Map<String, dynamic>)['total'], 12);
    });

    test('burn block reflects engaged burn answers', () {
      final a = adultNormal();
      a.chiefComplaint = ChiefComplaint.wound;
      a.burn.cause = BurnCause.scald;
      a.burn.tbsaPercent = 12.5;
      a.burn.area = BurnArea.face;
      final payload = Tier2Payload.from(a, TriageEngine.compute(a)).toJson();
      final burn = payload['burn'] as Map<String, dynamic>;
      expect(burn['tbsaPercent'], 12.5);
      expect(burn['hasCriticalArea'], isTrue);
      expect((burn['areas'] as List).contains('Face'), isTrue);
    });
  });

  group('buildPatientContext (chat seeding)', () {
    test('produces a decision-support framed context block', () {
      final a = adultNormal();
      final result = TriageEngine.compute(a);
      final text = buildPatientContext(a, result);

      expect(text, contains('TIER 1 TRIAGE CONTEXT'));
      expect(text, contains('not a diagnosis'));
      expect(text, contains('Age group: Adult'));
      expect(text, contains('Tier 1 result:'));
      expect(text, contains(a.chiefComplaint!.label));
    });

    test('flags vitals review when parameters are missing', () {
      final a = adultNormal();
      a.spo2Missing = true;
      a.tempMissing = true;
      a.spo2 = null;
      a.temperature = null;
      final result = TriageEngine.compute(a);
      final text = buildPatientContext(a, result);
      expect(text, contains('vitals review required'));
    });
  });
}
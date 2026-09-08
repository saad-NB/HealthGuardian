import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/engine.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/record.dart';
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

  group('Record v2.1 tier2 block', () {
    test('computeRecord uses schema version 2.1', () {
      final rec = TriageEngine.computeRecord(adultNormal());
      expect(rec.version, '2.1');
      expect(rec.tier2, isNull);
    });

    test('withTier2 preserves id/timestamp/version and attaches the block', () {
      final base = TriageEngine.computeRecord(adultNormal());
      const ai = Tier2Assessment(
        suggestion: TriageTier.p2,
        summary: '- line1\n- line2\n- line3\n- line4',
      );
      final updated = base.withTier2(ai);

      expect(updated.triageId, base.triageId);
      expect(updated.timestamp, base.timestamp);
      expect(updated.version, base.version);
      expect(updated.finalTier, base.finalTier);
      expect(updated.tier2?.suggestion, TriageTier.p2);

      // finalTier stays authoritative Tier 1 even when AI escalates.
      expect(updated.aiEscalated, isTrue);
      expect(updated.finalTier, TriageTier.p5);
    });

    test('round-trips through JSON with the tier2 block intact', () {
      final base = TriageEngine.computeRecord(adultNormal());
      const ai = Tier2Assessment(
        suggestion: TriageTier.p1,
        summary: '- x\n- y\n- z\n- w',
        elapsedMs: 4022,
      );
      final json = base.withTier2(ai).toJson();
      final restored = TriageRecord.fromJson(json);

      expect(restored.triageId, base.triageId);
      expect(restored.version, '2.1');
      expect(restored.tier2?.suggestion, TriageTier.p1);
      expect(restored.tier2?.summary, '- x\n- y\n- z\n- w');
      expect(restored.tier2?.elapsedMs, 4022);
      expect(restored.aiEscalated, isTrue);
    });

    test('fromJson tolerates a legacy v2.0 record (no tier2 key)', () {
      final legacyJson = TriageEngine.computeRecord(adultNormal()).toJson()
        ..remove('tier2')
        ..['version'] = '2.0';
      final restored = TriageRecord.fromJson(legacyJson);
      expect(restored.version, '2.0');
      expect(restored.tier2, isNull);
      expect(restored.finalTier, isNotNull);
    });

    test('advisory-only AI (no suggestion) sets no escalation flag', () {
      final base = TriageEngine.computeRecord(adultNormal());
      final updated = base.withTier2(const Tier2Assessment(summary: '- note'));
      expect(updated.aiEscalated, isFalse);
    });
  });
}
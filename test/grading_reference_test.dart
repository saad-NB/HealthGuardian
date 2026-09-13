import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/config/clinical_thresholds.dart';

void main() {
  group('NEWS2 SpO2 scoring (RCP Table 1, Scale 1)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.spO2Score(90), 3);
      expect(News2Thresholds.spO2Score(91), 3);
      expect(News2Thresholds.spO2Score(92), 2);
      expect(News2Thresholds.spO2Score(93), 2);
      expect(News2Thresholds.spO2Score(94), 1);
      expect(News2Thresholds.spO2Score(95), 1);
      expect(News2Thresholds.spO2Score(96), 0);
      expect(News2Thresholds.spO2Score(100), 0);
    });
  });

  group('NEWS2 air or oxygen scoring', () {
    test('air is 0, supplemental oxygen is 2', () {
      expect(News2Thresholds.airOrOxygenScore(false), 0);
      expect(News2Thresholds.airOrOxygenScore(true), 2);
    });
  });

  group('NEWS2 SpO2 Scale 2 scoring (RCP Table 2)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.spO2Scale2Score(83), 3);
      expect(News2Thresholds.spO2Scale2Score(84), 2);
      expect(News2Thresholds.spO2Scale2Score(85), 2);
      expect(News2Thresholds.spO2Scale2Score(86), 1);
      expect(News2Thresholds.spO2Scale2Score(87), 1);
      expect(News2Thresholds.spO2Scale2Score(88), 0);
      expect(News2Thresholds.spO2Scale2Score(92), 0);
      expect(News2Thresholds.spO2Scale2Score(93), 1);
      expect(News2Thresholds.spO2Scale2Score(94), 1);
      expect(News2Thresholds.spO2Scale2Score(95), 2);
      expect(News2Thresholds.spO2Scale2Score(96), 2);
      expect(News2Thresholds.spO2Scale2Score(97), 3);
    });
  });

  group('NEWS2 AVPU consciousness scoring (project spec §5.1)', () {
    test('A=0, V=2, P/U=3, unknown fails closed to 3', () {
      expect(News2Thresholds.avpuConsciousnessScore('A'), 0);
      expect(News2Thresholds.avpuConsciousnessScore('V'), 2);
      expect(News2Thresholds.avpuConsciousnessScore('P'), 3);
      expect(News2Thresholds.avpuConsciousnessScore('U'), 3);
      expect(News2Thresholds.avpuConsciousnessScore('a'), 0);
      expect(News2Thresholds.avpuConsciousnessScore('x'), 3);
    });
  });

  group('NEWS2 systolic BP scoring (RCP Table 1)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.systolicBpScore(89), 3);
      expect(News2Thresholds.systolicBpScore(90), 3);
      expect(News2Thresholds.systolicBpScore(91), 2);
      expect(News2Thresholds.systolicBpScore(100), 2);
      expect(News2Thresholds.systolicBpScore(101), 1);
      expect(News2Thresholds.systolicBpScore(110), 1);
      expect(News2Thresholds.systolicBpScore(111), 0);
      expect(News2Thresholds.systolicBpScore(219), 0);
      expect(News2Thresholds.systolicBpScore(220), 3);
    });
  });

  group('NEWS2 heart rate scoring (RCP Table 1)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.heartRateScore(39), 3);
      expect(News2Thresholds.heartRateScore(40), 3);
      expect(News2Thresholds.heartRateScore(41), 1);
      expect(News2Thresholds.heartRateScore(50), 1);
      expect(News2Thresholds.heartRateScore(51), 0);
      expect(News2Thresholds.heartRateScore(90), 0);
      expect(News2Thresholds.heartRateScore(91), 1);
      expect(News2Thresholds.heartRateScore(110), 1);
      expect(News2Thresholds.heartRateScore(111), 2);
      expect(News2Thresholds.heartRateScore(130), 2);
      expect(News2Thresholds.heartRateScore(131), 3);
    });
  });

  group('NEWS2 temperature scoring (RCP Table 1)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.temperatureScore(34.9), 3);
      expect(News2Thresholds.temperatureScore(35.0), 3);
      expect(News2Thresholds.temperatureScore(35.1), 1);
      expect(News2Thresholds.temperatureScore(36.0), 1);
      expect(News2Thresholds.temperatureScore(36.1), 0);
      expect(News2Thresholds.temperatureScore(38.0), 0);
      expect(News2Thresholds.temperatureScore(38.1), 1);
      expect(News2Thresholds.temperatureScore(39.0), 1);
      expect(News2Thresholds.temperatureScore(39.1), 2);
    });
  });

  group('NEWS2 respiratory rate scoring (RCP Table 1)', () {
    test('every boundary published value', () {
      expect(News2Thresholds.respiratoryRateScore(8), 3);
      expect(News2Thresholds.respiratoryRateScore(9), 1);
      expect(News2Thresholds.respiratoryRateScore(11), 1);
      expect(News2Thresholds.respiratoryRateScore(12), 0);
      expect(News2Thresholds.respiratoryRateScore(20), 0);
      expect(News2Thresholds.respiratoryRateScore(21), 2);
      expect(News2Thresholds.respiratoryRateScore(24), 2);
      expect(News2Thresholds.respiratoryRateScore(25), 3);
    });
  });

  group('NEWS2 consciousness scoring (AVPU)', () {
    test('alert is 0, anything else is 3', () {
      expect(News2Thresholds.consciousnessScore(true), 0);
      expect(News2Thresholds.consciousnessScore(false), 3);
    });
  });

  group('NEWS2 aggregate', () {
    test('equals the sum of its components', () {
      expect(
        News2Thresholds.aggregate(
          spo2: 3,
          airOrOxygen: 2,
          systolicBp: 1,
          heartRate: 3,
          temperature: 2,
          respiratoryRate: 3,
          consciousness: 3,
        ),
        17,
      );
      expect(
        News2Thresholds.aggregate(
          spo2: 0,
          airOrOxygen: 0,
          systolicBp: 0,
          heartRate: 0,
          temperature: 0,
          respiratoryRate: 0,
          consciousness: 0,
        ),
        0,
      );
    });

    test('sum identity holds over a seeded sweep', () {
      final random = Random(42);
      for (var i = 0; i < 200; i++) {
        final spo2 = random.nextInt(4);
        final airOrOxygen = random.nextInt(3);
        final systolicBp = random.nextInt(4);
        final heartRate = random.nextInt(4);
        final temperature = random.nextInt(4);
        final respiratoryRate = random.nextInt(4);
        final consciousness = random.nextInt(4) == 0 ? 3 : 0;
        expect(
          News2Thresholds.aggregate(
            spo2: spo2,
            airOrOxygen: airOrOxygen,
            systolicBp: systolicBp,
            heartRate: heartRate,
            temperature: temperature,
            respiratoryRate: respiratoryRate,
            consciousness: consciousness,
          ),
          spo2 + airOrOxygen + systolicBp + heartRate + temperature +
              respiratoryRate + consciousness,
        );
      }
    });
  });

  group('NEWS2 clinical risk bands (RCP Figure 1)', () {
    test('every band boundary value', () {
      expect(News2Thresholds.clinicalRisk(0), TriageLevel.routine);
      expect(News2Thresholds.clinicalRisk(1), TriageLevel.routine);
      expect(News2Thresholds.clinicalRisk(4), TriageLevel.routine);
      expect(News2Thresholds.clinicalRisk(5), TriageLevel.urgent);
      expect(News2Thresholds.clinicalRisk(6), TriageLevel.urgent);
      expect(News2Thresholds.clinicalRisk(7), TriageLevel.emergency);
      expect(News2Thresholds.clinicalRisk(20), TriageLevel.emergency);
    });
  });

  group('GCS components (Teasdale & Jennett)', () {
    test('eye opening maps 1-4', () {
      expect(GcsThresholds.eyeOpening('spontaneous'), 4);
      expect(GcsThresholds.eyeOpening('voice'), 3);
      expect(GcsThresholds.eyeOpening('pain'), 2);
      expect(GcsThresholds.eyeOpening('none'), 1);
    });
    test('eye opening is case-insensitive', () {
      expect(GcsThresholds.eyeOpening('Spontaneous'), 4);
    });
    test('eye opening fails closed on unknown input', () {
      expect(GcsThresholds.eyeOpening('garbage'), 1);
    });

    test('verbal response maps 1-5', () {
      expect(GcsThresholds.verbalResponse('oriented'), 5);
      expect(GcsThresholds.verbalResponse('confused'), 4);
      expect(GcsThresholds.verbalResponse('words'), 3);
      expect(GcsThresholds.verbalResponse('sounds'), 2);
      expect(GcsThresholds.verbalResponse('none'), 1);
    });
    test('verbal response fails closed on unknown input', () {
      expect(GcsThresholds.verbalResponse('garbage'), 1);
    });

    test('motor response maps 1-6', () {
      expect(GcsThresholds.motorResponse('obeys'), 6);
      expect(GcsThresholds.motorResponse('localises'), 5);
      expect(GcsThresholds.motorResponse('withdraws'), 4);
      expect(GcsThresholds.motorResponse('flexion'), 3);
      expect(GcsThresholds.motorResponse('extension'), 2);
      expect(GcsThresholds.motorResponse('none'), 1);
    });
    test('motor response fails closed on unknown input', () {
      expect(GcsThresholds.motorResponse('garbage'), 1);
    });

    test('total equals sum of components (best and worst case)', () {
      expect(
        GcsThresholds.total(eye: 4, verbal: 5, motor: 6),
        15,
      );
      expect(
        GcsThresholds.total(eye: 1, verbal: 1, motor: 1),
        3,
      );
    });
  });

  group('GCS triage levels (RCS)', () {
    test('every boundary value', () {
      expect(GcsThresholds.triageLevel(3), TriageLevel.emergency);
      expect(GcsThresholds.triageLevel(8), TriageLevel.emergency);
      expect(GcsThresholds.triageLevel(9), TriageLevel.urgent);
      expect(GcsThresholds.triageLevel(13), TriageLevel.urgent);
      expect(GcsThresholds.triageLevel(14), TriageLevel.routine);
      expect(GcsThresholds.triageLevel(15), TriageLevel.routine);
    });
  });

  group('Burn TBSA levels (ABA)', () {
    test('adult boundaries', () {
      expect(BurnThresholds.tbsaLevel(9.9), TriageLevel.routine);
      expect(BurnThresholds.tbsaLevel(10), TriageLevel.urgent);
      expect(BurnThresholds.tbsaLevel(19.9), TriageLevel.urgent);
      expect(BurnThresholds.tbsaLevel(20), TriageLevel.emergency);
      expect(BurnThresholds.tbsaLevel(25), TriageLevel.emergency);
    });
    test('pediatric boundaries are lower', () {
      expect(BurnThresholds.tbsaLevel(4.9, isPediatric: true),
          TriageLevel.routine);
      expect(BurnThresholds.tbsaLevel(5, isPediatric: true),
          TriageLevel.urgent);
      expect(BurnThresholds.tbsaLevel(9.9, isPediatric: true),
          TriageLevel.urgent);
      expect(BurnThresholds.tbsaLevel(10, isPediatric: true),
          TriageLevel.emergency);
    });
  });

  group('Burn critical locations (ABA)', () {
    test('each critical substring is caught', () {
      expect(BurnThresholds.hasCriticalLocation('face'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('hands'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('both feet'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('genitalia'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('right knee joint'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('perineum'), isTrue);
      expect(BurnThresholds.hasCriticalLocation('circumferential arm'),
          isTrue);
    });
    test('benign locations and casing', () {
      expect(BurnThresholds.hasCriticalLocation('thigh'), isFalse);
      expect(BurnThresholds.hasCriticalLocation('Face'), isTrue);
    });
  });

  }
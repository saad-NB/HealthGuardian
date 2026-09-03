import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/models/medgemma_files.dart';
import 'package:healthguardian/config/clinical_thresholds.dart';

void main() {
  test('MedGemma file constants are present and consistent', () {
    expect(MedGemmaFiles.all.length, 2);
    expect(MedGemmaFiles.model.filename, 'medgemma-1.5-4b-it-Q4_K_M.gguf');
    expect(MedGemmaFiles.model.isMmproj, isFalse);
    expect(MedGemmaFiles.mmproj.isMmproj, isTrue);
    expect(MedGemmaFiles.totalBytes, greaterThan(0));
    expect(
      MedGemmaFiles.byFilename(MedGemmaFiles.mmproj.filename),
      same(MedGemmaFiles.mmproj),
    );
  });

  test('NEWS2 SpO2 scoring matches RCP Table 1', () {
    expect(News2Thresholds.spO2Score(90), 3);
    expect(News2Thresholds.spO2Score(91), 3);
    expect(News2Thresholds.spO2Score(92), 2);
    expect(News2Thresholds.spO2Score(93), 2);
    expect(News2Thresholds.spO2Score(94), 1);
    expect(News2Thresholds.spO2Score(95), 1);
    expect(News2Thresholds.spO2Score(96), 0);
    expect(News2Thresholds.spO2Score(100), 0);
  });

  test('NEWS2 heart rate scoring matches RCP Table 1', () {
    expect(News2Thresholds.heartRateScore(35), 3);
    expect(News2Thresholds.heartRateScore(40), 3);
    expect(News2Thresholds.heartRateScore(45), 1);
    expect(News2Thresholds.heartRateScore(70), 0);
    expect(News2Thresholds.heartRateScore(100), 1);
    expect(News2Thresholds.heartRateScore(120), 2);
    expect(News2Thresholds.heartRateScore(135), 3);
  });

  test('GCS triage levels match RCS guidelines', () {
    expect(GcsThresholds.triageLevel(3), TriageLevel.emergency);
    expect(GcsThresholds.triageLevel(8), TriageLevel.emergency);
    expect(GcsThresholds.triageLevel(9), TriageLevel.urgent);
    expect(GcsThresholds.triageLevel(13), TriageLevel.urgent);
    expect(GcsThresholds.triageLevel(14), TriageLevel.routine);
    expect(GcsThresholds.triageLevel(15), TriageLevel.routine);
  });

  test('Burn TBSA levels match ABA criteria', () {
    expect(BurnThresholds.tbsaLevel(5), TriageLevel.routine);
    expect(BurnThresholds.tbsaLevel(10), TriageLevel.urgent);
    expect(BurnThresholds.tbsaLevel(15), TriageLevel.urgent);
    expect(BurnThresholds.tbsaLevel(20), TriageLevel.emergency);
    expect(BurnThresholds.tbsaLevel(30), TriageLevel.emergency);
  });

  test('Pediatric burn thresholds are lower', () {
    expect(BurnThresholds.tbsaLevel(4, isPediatric: true), TriageLevel.routine);
    expect(BurnThresholds.tbsaLevel(5, isPediatric: true), TriageLevel.urgent);
    expect(BurnThresholds.tbsaLevel(10, isPediatric: true), TriageLevel.emergency);
  });

  test('Red flags fire at correct thresholds', () {
    expect(RedFlags.severeImpairment(8), isTrue);
    expect(RedFlags.severeImpairment(9), isFalse);
    expect(RedFlags.hypotension(90), isTrue);
    expect(RedFlags.hypotension(91), isFalse);
    expect(RedFlags.severeHypoxia(91, false), isTrue);
    expect(RedFlags.severeHypoxia(91, true), isFalse);
    expect(RedFlags.criticalRespiratoryRate(8), isTrue);
    expect(RedFlags.criticalRespiratoryRate(12), isFalse);
    expect(RedFlags.criticalRespiratoryRate(25), isTrue);
    expect(RedFlags.criticalHeartRate(40), isTrue);
    expect(RedFlags.criticalHeartRate(70), isFalse);
    expect(RedFlags.criticalHeartRate(131), isTrue);
    expect(RedFlags.criticalTemperature(35.0), isTrue);
    expect(RedFlags.criticalTemperature(36.5), isFalse);
    expect(RedFlags.criticalTemperature(39.1), isTrue);
  });
}

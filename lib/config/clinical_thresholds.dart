/// Central configuration for all clinical thresholds and decision rules.
library;

/// RULE: Every value here MUST have an inline citation to its published source.
/// Any change to a threshold requires a corresponding entry in docs/DECISIONS.md.
/// Git history on this file is treated as an audit trail — avoid squashing commits.
///
/// Sources:
///   - NEWS2: Royal College of Physicians, "National Early Warning Score 2" (2017)
///   - GCS: Teasdale & Jennett, Lancet (1974); validated thresholds per RCS
///   - Burn TBSA: Rule of Nines (Wallace, 1951); Lund & Browder for pediatric
///   - Skin classifier risk tiers: internal calibration (see docs/MODEL_CARDS/)

enum TriageLevel { routine, urgent, emergency }

/// NEWS2 aggregate scoring bands.
/// Source: Royal College of Physicians, NEWS2 (2017), Table 1.
class News2Thresholds {
  News2Thresholds._();

  /// SpO2 Scale 1 thresholds (adults, %).
  /// <=91% = 3, 92-93% = 2, 94-95% = 1, >=96% = 0.
  static int spO2Score(double spo2) {
    if (spo2 <= 91) return 3;
    if (spo2 <= 93) return 2;
    if (spo2 <= 95) return 1;
    return 0;
  }

  /// SpO2 Scale 2 thresholds (adults with COPD / CO2 retention, %).
  /// <=83 = 3, 84-85 = 2, 86-87 = 1, 88-92 = 0, 93-94 = 1, 95-96 = 2, >=97 = 3.
  /// Source: RCP NEWS2 (2017), Table 2 (SpO2 Scale 2).
  static int spO2Scale2Score(double spo2) {
    if (spo2 <= 83) return 3;
    if (spo2 <= 85) return 2;
    if (spo2 <= 87) return 1;
    if (spo2 <= 92) return 0;
    if (spo2 <= 94) return 1;
    if (spo2 <= 96) return 2;
    return 3;
  }

  /// Air or oxygen breathing: Air = 0, supplemental O2 = 2.
  /// Source: RCP NEWS2, Table 1, row 2.
  static int airOrOxygenScore(bool onOxygen) => onOxygen ? 2 : 0;

  /// Systolic BP thresholds (mmHg).
  /// <=90 = 3, 91-100 = 2, 101-110 = 1, 111-219 = 0, >=220 = 3.
  /// Source: RCP NEWS2, Table 1, row 3.
  static int systolicBpScore(double sbp) {
    if (sbp <= 90) return 3;
    if (sbp <= 100) return 2;
    if (sbp <= 110) return 1;
    if (sbp <= 219) return 0;
    return 3;
  }

  /// Heart rate thresholds (beats/min).
  /// <=40 = 3, 41-50 = 1, 51-90 = 0, 91-110 = 1, 111-130 = 2, >=131 = 3.
  /// Source: RCP NEWS2, Table 1, row 4.
  static int heartRateScore(double hr) {
    if (hr <= 40) return 3;
    if (hr <= 50) return 1;
    if (hr <= 90) return 0;
    if (hr <= 110) return 1;
    if (hr <= 130) return 2;
    return 3;
  }

  /// Temperature thresholds (degrees C).
  /// <=35.0 = 3, 35.1-36.0 = 1, 36.1-38.0 = 0, 38.1-39.0 = 1, >=39.1 = 2.
  /// Source: RCP NEWS2, Table 1, row 5.
  static int temperatureScore(double temp) {
    if (temp <= 35.0) return 3;
    if (temp <= 36.0) return 1;
    if (temp <= 38.0) return 0;
    if (temp <= 39.0) return 1;
    return 2;
  }

  /// Respiratory rate thresholds (breaths/min).
  /// <=8 = 3, 9-11 = 1, 12-20 = 0, 21-24 = 2, >=25 = 3.
  /// Source: RCP NEWS2, Table 1, row 6.
  static int respiratoryRateScore(double rr) {
    if (rr <= 8) return 3;
    if (rr <= 11) return 1;
    if (rr <= 20) return 0;
    if (rr <= 24) return 2;
    return 3;
  }

  /// Consciousness: AVPU scale. Alert = 0, Voice/Pain/Unresponsive = 3.
  /// Source: RCP NEWS2, Table 1, row 7.
  static int consciousnessScore(bool isAlert) => isAlert ? 0 : 3;

  /// Consciousness by AVPU letter (project adaptation).
  /// 'A' = 0, 'V' = 2, 'P' = 3, 'U' = 3. Unknown fails closed to 3.
  /// NOTE: deviates from standard NEWS2 ('V' = 3) per project Tier 1 spec
  /// §5.1/§5.2 (AVPU gradient shared with pediatric scales). See ADR-009.
  static int avpuConsciousnessScore(String avpu) {
    switch (avpu.toUpperCase()) {
      case 'A':
        return 0;
      case 'V':
        return 2;
      case 'P':
      case 'U':
        return 3;
      default:
        return 3;
    }
  }

  /// Aggregate NEWS2 score from individual component scores.
  static int aggregate({
    required int spo2,
    required int airOrOxygen,
    required int systolicBp,
    required int heartRate,
    required int temperature,
    required int respiratoryRate,
    required int consciousness,
  }) {
    return spo2 +
        airOrOxygen +
        systolicBp +
        heartRate +
        temperature +
        respiratoryRate +
        consciousness;
  }

  /// NEWS2 aggregate score to clinical risk.
  /// 0 = Low, 1-4 = Low, 3 in any single parameter = Low-Medium,
  /// 5-6 = Medium, >=7 = High.
  /// Source: RCP NEWS2 (2017), Figure 1.
  static TriageLevel clinicalRisk(int aggregateScore) {
    if (aggregateScore >= 7) return TriageLevel.emergency;
    if (aggregateScore >= 5) return TriageLevel.urgent;
    return TriageLevel.routine;
  }
}

/// Glasgow Coma Scale scoring.
/// Source: Teasdale & Jennett, Lancet (1974); RCS Clinical Standards.
class GcsThresholds {
  GcsThresholds._();

  /// Eye opening: 1-4.
  static int eyeOpening(String response) {
    switch (response.toLowerCase()) {
      case 'spontaneous':
        return 4;
      case 'voice':
        return 3;
      case 'pain':
        return 2;
      case 'none':
        return 1;
      default:
        return 1;
    }
  }

  /// Verbal response: 1-5.
  static int verbalResponse(String response) {
    switch (response.toLowerCase()) {
      case 'oriented':
        return 5;
      case 'confused':
        return 4;
      case 'inappropriate':
        return 3;
      case 'incomprehensible':
        return 2;
      case 'none':
        return 1;
      default:
        return 1;
    }
  }

  /// Motor response: 1-6.
  static int motorResponse(String response) {
    switch (response.toLowerCase()) {
      case 'obeys':
        return 6;
      case 'localizes':
        return 5;
      case 'flexion':
        return 4;
      case 'abnormal':
        return 3;
      case 'extension':
        return 2;
      case 'none':
        return 1;
      default:
        return 1;
    }
  }

  /// Total GCS score.
  static int total({
    required int eye,
    required int verbal,
    required int motor,
  }) {
    return eye + verbal + motor;
  }

  /// GCS to triage level.
  /// Source: RCS Trauma guidelines.
  /// GCS <=8 = Emergency (severe), 9-13 = Urgent (moderate), 14-15 = Routine.
  static TriageLevel triageLevel(int gcs) {
    if (gcs <= 8) return TriageLevel.emergency;
    if (gcs <= 13) return TriageLevel.urgent;
    return TriageLevel.routine;
  }
}

/// Burn injury thresholds.
/// TBSA: Rule of Nines (Wallace, 1951).
/// Depth: superficial/partial-thick/full-thick classification.
class BurnThresholds {
  BurnThresholds._();

  /// TBSA percentage classification.
  /// Source: ABA (American Burn Association) referral criteria.
  /// >=20% adult or >=10% pediatric = Emergency.
  /// 10-19% adult or 5-9% pediatric = Urgent.
  /// <10% adult or <5% pediatric = Routine (with monitoring).
  static TriageLevel tbsaLevel(double tbsaPercent, {bool isPediatric = false}) {
    final emergencyThreshold = isPediatric ? 10.0 : 20.0;
    final urgentThreshold = isPediatric ? 5.0 : 10.0;
    if (tbsaPercent >= emergencyThreshold) return TriageLevel.emergency;
    if (tbsaPercent >= urgentThreshold) return TriageLevel.urgent;
    return TriageLevel.routine;
  }

  /// Full-thickness burns to face, hands, feet, genitalia, or major joints
  /// are automatically Urgent regardless of TBSA.
  /// Source: ABA referral criteria.
  static bool hasCriticalLocation(String location) {
    const critical = [
      'face', 'hands', 'feet', 'genitalia', 'joint',
      'perineum', 'circumferential',
    ];
    return critical.any((c) => location.toLowerCase().contains(c));
  }
}

/// Skin classifier risk tier thresholds.
/// t_susp: threshold above which a class is "suspicious".
/// t_high: threshold above which a class is "high-risk".
/// Source: internal calibration — see docs/MODEL_CARDS/skin_classifier.md.
class SkinClassifierThresholds {
  SkinClassifierThresholds._();

  /// Probability threshold for "suspicious" tier.
  static const double tSuspicious = 0.4;

  /// Probability threshold for "high-risk" tier.
  static const double tHighRisk = 0.7;

  /// Map classifier risk tier to triage level.
  static TriageLevel triageLevel(String riskTier) {
    switch (riskTier.toLowerCase()) {
      case 'high':
        return TriageLevel.emergency;
      case 'suspicious':
        return TriageLevel.urgent;
      default:
        return TriageLevel.routine;
    }
  }
}

/// Hard red-flag overrides that force Emergency regardless of other scores.
/// These are absolute safety nets — if ANY flag fires, triage is Emergency.
class RedFlags {
  RedFlags._();

  /// GCS <= 8 (unable to protect airway).
  static bool severeImpairment(int gcs) => gcs <= 8;

  /// Systolic BP <= 90 mmHg (shock).
  static bool hypotension(double sbp) => sbp <= 90;

  /// SpO2 <= 91% on room air (severe hypoxia).
  static bool severeHypoxia(double spo2, bool onOxygen) =>
      spo2 <= 91 && !onOxygen;

  /// Respiratory rate <= 8 or >= 25.
  static bool criticalRespiratoryRate(double rr) => rr <= 8 || rr >= 25;

  /// Heart rate <= 40 or >= 131.
  static bool criticalHeartRate(double hr) => hr <= 40 || hr >= 131;

  /// Temperature <= 35.0 or >= 39.1.
  static bool criticalTemperature(double temp) => temp <= 35.0 || temp >= 39.1;

  /// Check all red flags. Returns true if ANY flag fires.
  static bool anyFire({
    required int gcs,
    required double sbp,
    required double spo2,
    bool onOxygen = false,
    required double rr,
    required double hr,
    required double temp,
  }) {
    return severeImpairment(gcs) ||
        hypotension(sbp) ||
        severeHypoxia(spo2, onOxygen) ||
        criticalRespiratoryRate(rr) ||
        criticalHeartRate(hr) ||
        criticalTemperature(temp);
  }
}

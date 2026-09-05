import '../config/clinical_thresholds.dart';
import 'models.dart';

/// Tier 1 triage decision engine.
///
/// Implements Tier 1 spec:
///   - §4      Emergency danger-sign gates (any YES -> immediate P1)
///   - §5.1    Adult NEWS2 scoring + tier mapping (>=16 years)
///   - §21     Missing-vitals policy (hybrid A+C): partial scoring +
///             context substitution, P3 floor, vitalReviewRequired.
///   - PRINCIPLE 2 (max-merge, escalate-only) and PRINCIPLE 5 (fail-closed).
///
/// Pure and synchronous so UI stays below the 1 s compute budget and the
/// logic is trivially unit-testable.
class TriageEngine {
  TriageEngine._();

  static const TriageTier _missingVitalsFloor = TriageTier.p3;

  static const List<({String id, int order})> _dangerSignOrder = [
    (id: 'A1', order: 1),
    (id: 'A2', order: 2),
    (id: 'A3', order: 3),
    (id: 'A4', order: 4),
    (id: 'A5', order: 5),
    (id: 'A6', order: 6),
    (id: 'A7', order: 7),
    (id: 'A8', order: 8),
    (id: 'A9', order: 9),
    (id: 'A10', order: 10),
    (id: 'A11', order: 11),
    (id: 'A12', order: 12),
    (id: 'A13', order: 13),
    (id: 'A14', order: 14),
    (id: 'A15', order: 15),
  ];

  static String dangerReason(String id) => 'Danger gate: $id';

  /// Compute the triage result for a session.
  /// Never throws: any incomplete/invalid input fails closed to a higher tier.
  static TriageResult compute(TriageAnswers a) {
    final age = a.ageGroup;
    if (age == null) {
      return TriageResult(
        tier: _missingVitalsFloor,
        reasons: const ['Age was not selected.'],
        vitalReviewRequired: true,
      );
    }

    final reasons = <String>[];
    var tier = _applyDangerGates(a, reasons);

    if (!age.usesNews2) {
      return _pediatricSafetyResult(tier, reasons);
    }

    final news2 = _scoreAdultNews2(a, reasons);
    var mapped = _tierFromNews2(news2);
    reasons.add('NEWS2 score: ${news2.aggregate}');

    var reviewRequired = news2.hasMissingVitals;
    tier = tier.atMostUrgent(mapped);
    if (reviewRequired) {
      tier = tier.atMostUrgent(_missingVitalsFloor);
    }

    return TriageResult(
      tier: tier,
      reasons: reasons,
      aggregate: news2.aggregate,
      vitalReviewRequired: reviewRequired,
    );
  }

  static TriageTier _applyDangerGates(TriageAnswers a, List<String> reasons) {
    if (a.dangerSigns.isEmpty) return TriageTier.p5;
    for (final g in _dangerSignOrder) {
      if (a.dangerSigns.contains(g.id)) {
        reasons.add(dangerReason(g.id));
      }
    }
    return TriageTier.p1;
  }

  static TriageResult _pediatricSafetyResult(
      TriageTier tier, List<String> reasons) {
    if (tier == TriageTier.p1) {
      return TriageResult(
        tier: TriageTier.p1,
        reasons: reasons,
        vitalReviewRequired: true,
        decisionSupport: true,
      );
    }
    reasons.add(
        'Age-specific scales (Peds-NEWS2 / PEWS) are under development.');
    reasons.add('Full clinical review recommended.');
    return TriageResult(
      tier: TriageTier.p3,
      reasons: reasons,
      vitalReviewRequired: true,
    );
  }

  static bool _physiologicallyPossible(String field, double value) {
    switch (field) {
      case 'rr':
        return value >= 4 && value <= 60;
      case 'spo2':
        return value >= 50 && value <= 100;
      case 'sbp':
        return value >= 60 && value <= 260;
      case 'hr':
        return value >= 20 && value <= 220;
      case 'temp':
        return value >= 34.0 && value <= 43.0;
      default:
        return false;
    }
  }

  static _AdultNews2 _scoreAdultNews2(TriageAnswers a, List<String> reasons) {
    final hasRr =
        a.respiratoryRate != null &&
        _physiologicallyPossible('rr', a.respiratoryRate!);
    final hasSpo2 =
        !a.spo2Missing &&
        a.spo2 != null &&
        _physiologicallyPossible('spo2', a.spo2!);
    final hasSbp =
        a.systolicBp != null && _physiologicallyPossible('sbp', a.systolicBp!);
    final hasHr =
        a.heartRate != null && _physiologicallyPossible('hr', a.heartRate!);
    final hasTemp =
        !a.tempMissing &&
        a.temperature != null &&
        _physiologicallyPossible('temp', a.temperature!);
    final hasConsc = a.consciousness != null;

    int? rrScore;
    if (hasRr) {
      rrScore = News2Thresholds.respiratoryRateScore(a.respiratoryRate!);
      _noteThree(reasons, 'Respiratory rate', a.respiratoryRate!, rrScore);
    }

    int? sbpScore;
    if (hasSbp) {
      sbpScore = News2Thresholds.systolicBpScore(a.systolicBp!);
      _noteThree(reasons, 'Systolic BP', a.systolicBp!, sbpScore);
    }

    int? hrScore;
    if (hasHr) {
      hrScore = News2Thresholds.heartRateScore(a.heartRate!);
      _noteThree(reasons, 'Heart rate', a.heartRate!, hrScore);
    }

    final o2Score = News2Thresholds.airOrOxygenScore(a.onOxygen);
    if (a.onOxygen) reasons.add('On supplemental oxygen (2 points).');

    int? spo2Score;
    if (hasSpo2) {
      spo2Score = a.copdCo2Retention
          ? News2Thresholds.spO2Scale2Score(a.spo2!)
          : News2Thresholds.spO2Score(a.spo2!);
      _noteThree(reasons, 'SpO2', a.spo2!, spo2Score);
    } else if (rrScore != null && rrScore >= 2) {
      spo2Score = 3;
      reasons.add(
          'SpO2 not measured with a breathing concern - treated as severe.');
    } else {
      reasons.add('SpO2 not measured.');
    }

    int? tempScore;
    if (hasTemp) {
      tempScore = News2Thresholds.temperatureScore(a.temperature!);
      _noteThree(reasons, 'Temperature', a.temperature!, tempScore);
    } else {
      reasons.add('Temperature not measured.');
    }

    int? conscScore;
    if (hasConsc) {
      conscScore =
          News2Thresholds.avpuConsciousnessScore(a.consciousness!.letter);
      if (conscScore == 3) reasons.add('Consciousness: ${a.consciousness!.label}.');
    }

    final missing = <String>[
      if (!hasRr) 'respiratory rate',
      if (!hasSbp) 'systolic BP',
      if (!hasHr) 'heart rate',
      if (!hasConsc) 'consciousness',
    ];
    final hasMissingVitals = missing.isNotEmpty || !hasSpo2 || !hasTemp;

    final aggregate = (rrScore ?? 0) +
        (spo2Score ?? 0) +
        (sbpScore ?? 0) +
        (hrScore ?? 0) +
        (tempScore ?? 0) +
        o2Score +
        (conscScore ?? 0);

    return _AdultNews2(
      aggregate: aggregate,
      anyParameterThree:
          rrScore == 3 ||
              spo2Score == 3 ||
              sbpScore == 3 ||
              hrScore == 3 ||
              tempScore == 3 ||
              conscScore == 3,
      hasMissingVitals: hasMissingVitals,
    );
  }

  static void _noteThree(List<String> reasons, String label, double value,
      int? score) {
    if (score == null || score < 3) return;
    final display =
        value == value.roundToDouble() ? value.toInt().toString() : '$value';
    reasons.add('$label $display scoring 3 points.');
  }

  /// Spec §5.1 NEWS2 tier mapping.
  static TriageTier _tierFromNews2(_AdultNews2 n) {
    if (n.aggregate >= 7 || n.anyParameterThree) return TriageTier.p1;
    if (n.aggregate >= 5) return TriageTier.p2;
    if (n.aggregate >= 3) return TriageTier.p3;
    if (n.aggregate >= 1) return TriageTier.p4;
    return TriageTier.p5;
  }
}

class _AdultNews2 {
  const _AdultNews2({
    required this.aggregate,
    required this.anyParameterThree,
    required this.hasMissingVitals,
  });

  final int aggregate;
  final bool anyParameterThree;
  final bool hasMissingVitals;
}
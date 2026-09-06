import '../config/clinical_thresholds.dart';
import 'models.dart';
import 'probes.dart';

/// Tier 1 triage decision engine.
///
/// Implements Tier 1 spec:
///   - §4      Emergency danger-sign gates (any YES -> immediate P1)
///   - §5.1    Adult NEWS2 scoring + tier mapping (>=16 years)
///   - §5.2    Peds-NEWS2 scoring + tier mapping (1-15 years, age-bracketed)
///   - §5.3    Neonatal adapted PEWS (0-30 days)
///   - §6      Full GCS tier mapping (when indicated; AVPU via vitals)
///   - §7/§8   Chief-complaint D branch + scored E probes
///   - §9      Sepsis screen (qSOFA adult / pedSIRS 1-15y)
///   - §21     Missing-vitals policy: partial scoring + context
///             substitution, P3 floor, vitalReviewRequired
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

  static TriageTier _tierFromUrgency(int urgency) => switch (urgency) {
        1 => TriageTier.p1,
        2 => TriageTier.p2,
        3 => TriageTier.p3,
        4 => TriageTier.p4,
        _ => TriageTier.p5,
      };

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

    if (tier == TriageTier.p1) {
      return TriageResult(
        tier: TriageTier.p1,
        reasons: reasons,
        scale: age.scale,
        vitalReviewRequired: false,
      );
    }

    // === VITAL SIGNS (scale per §3 bracket) ===
    final vital = _vitalOutcome(a, age, reasons);
    tier = tier.atMostUrgent(vital.tier);
    reasons.add('${age.scale.label} score: ${vital.score}');

    // === CONSCIOUSNESS / GCS (§6) — only when all components collected ===
    final gcsTotal = _gcsTotal(a);
    if (gcsTotal != null) {
      final gcsTier = _tierFromUrgency(GcsThresholds.tierFromGcs(
        gcsTotal,
        headInjury: a.chiefComplaint?.suggestsHeadInjury ?? false,
      ));
      tier = tier.atMostUrgent(gcsTier);
      reasons.add('GCS: $gcsTotal → ${gcsTier.label}');
    }

    // === CHIEF COMPLAINT + PROBES (§7/§8) ===
    final complaint = _complaintTier(a);
    if (complaint.tier != null) {
      tier = tier.atMostUrgent(complaint.tier!);
      reasons.add(
          'Complaint: ${a.chiefComplaint?.label ?? '?'} → ${complaint.tier!.label}');
    }

    // === SEPSIS SCREEN (§9) ===
    final sepsis = _sepsisTier(a);
    final sepsisReason = sepsis.reason;
    if (sepsis.tier != null && sepsisReason != null) {
      tier = tier.atMostUrgent(sepsis.tier!);
      reasons.add(sepsisReason);
    }

    return TriageResult(
      tier: tier,
      reasons: reasons,
      aggregate: vital.score,
      scale: age.scale,
      vitalReviewRequired: vital.review,
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

  // ---------------------------------------------------------------------
  // Vitals
  // ---------------------------------------------------------------------

  static _VitalOutcome _vitalOutcome(
      TriageAnswers a, AgeGroup age, List<String> reasons) {
    return switch (age.scale) {
      VitalScale.news2 => _scoreNews2(a, age, reasons),
      VitalScale.pedsNews2 => _scorePeds(a, age, reasons),
      VitalScale.pews => _scorePews(a, age, reasons),
    };
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

  /// Present, physiologically-possible value for a field (null otherwise).
  static double? _valueOf(TriageAnswers a, String field) {
    final v = switch (field) {
      'rr' => a.respiratoryRate,
      'spo2' => a.spo2,
      'sbp' => a.systolicBp,
      'hr' => a.heartRate,
      'temp' => a.temperature,
      _ => null,
    };
    if (v == null) return null;
    return _physiologicallyPossible(field, v) ? v : null;
  }

  static bool _isMissingSpo2(TriageAnswers a) =>
      a.spo2Missing || _valueOf(a, 'spo2') == null;

  static bool _isMissingTemp(TriageAnswers a) =>
      a.tempMissing || _valueOf(a, 'temp') == null;

  /// Full GCS aggregate, or null when not all three components are present.
  static int? _gcsTotal(TriageAnswers a) {
    final e = a.gcsEye;
    final v = a.gcsVerbal;
    final m = a.gcsMotor;
    if (e == null || v == null || m == null) return null;
    return e + v + m;
  }

  /// §21.5.1 — any single trigger means a missing SpO2 likely reflects
  /// hypoxia and gets a conservative substituted score.
  static bool _respiratoryConcern(TriageAnswers a, AgeGroup age) {
    if (a.chiefComplaint == ChiefComplaint.breathing) return true;
    if (a.onOxygen ?? false) return true;
    if (a.copdCo2Retention ?? false) return true;
    if (a.dangerSigns.contains('A4') || a.dangerSigns.contains('A5')) {
      return true;
    }
    // E-B1 inverted: "cannot speak full sentences" (No) is the concern.
    if (a.probeAnswers['E-B1'] == false) return true;
    if (a.probeAnswers['E-B3'] ?? false) return true;
    final rr = _valueOf(a, 'rr');
    if (rr != null) {
      final rrScore = _rrScore(age, rr);
      if (rrScore >= 2) return true;
    }
    return false;
  }

  /// §21.6.1 — fever/immmunocompromise/age-extreme context makes a missing
  /// temperature likely abnormal.
  static bool _temperatureConcern(TriageAnswers a, AgeGroup age) {
    if (a.chiefComplaint == ChiefComplaint.fever) return true;
    if (age.isUnderOneYear || age.isOlderAdult) return true;
    if (a.sepsis.f1 ?? false) return true;
    if (a.sepsis.f6 ?? false) return true;
    if (a.probeAnswers['E-F1'] ?? false) return true;
    return false;
  }

  static int _rrScore(AgeGroup age, double rr) {
    if (age.usesNews2) return News2Thresholds.respiratoryRateScore(rr);
    final bracket = age.pedsBracket ?? 'teen';
    return PedsNews2Thresholds.respiratoryRateScore(bracket, rr);
  }

  // ---- Adult NEWS2 (spec §5.1) -----------------------------------------

  static _VitalOutcome _scoreNews2(
      TriageAnswers a, AgeGroup age, List<String> reasons) {
    final rr = _valueOf(a, 'rr');
    final sbp = _valueOf(a, 'sbp');
    final hr = _valueOf(a, 'hr');
    final hasConsc = a.consciousness != null;

    int? rrScore;
    if (rr != null) {
      rrScore = News2Thresholds.respiratoryRateScore(rr);
      _noteThree(reasons, 'Respiratory rate', rr, rrScore);
    }

    int? sbpScore;
    if (sbp != null) {
      sbpScore = News2Thresholds.systolicBpScore(sbp);
      _noteThree(reasons, 'Systolic BP', sbp, sbpScore);
    }

    int? hrScore;
    if (hr != null) {
      hrScore = News2Thresholds.heartRateScore(hr);
      _noteThree(reasons, 'Heart rate', hr, hrScore);
    }

    final o2Score = News2Thresholds.airOrOxygenScore(a.onOxygen ?? false);
    if (a.onOxygen ?? false) reasons.add('On supplemental oxygen (2 points).');

    final spo2Missing = _isMissingSpo2(a);
    int? spo2Score;
    if (!spo2Missing) {
      spo2Score =
          (a.copdCo2Retention ?? false)
              ? News2Thresholds.spO2Scale2Score(a.spo2!)
              : News2Thresholds.spO2Score(a.spo2!);
      _noteThree(reasons, 'SpO2', a.spo2!, spo2Score);
    } else if (_respiratoryConcern(a, age)) {
      spo2Score = 3;
      reasons.add(
          'SpO2 not measured with a breathing concern - treated as severe.');
    } else {
      reasons.add('SpO2 not measured.');
    }

    final tempMissing = _isMissingTemp(a);
    int? tempScore;
    if (!tempMissing) {
      tempScore = News2Thresholds.temperatureScore(a.temperature!);
      _noteThree(reasons, 'Temperature', a.temperature!, tempScore);
    } else if (_temperatureConcern(a, age)) {
      tempScore = 3;
      reasons.add(
          'Temperature not measured with a fever concern - treated as severe.');
    } else {
      reasons.add('Temperature not measured.');
    }

    int? conscScore;
    if (hasConsc) {
      conscScore =
          News2Thresholds.avpuConsciousnessScore(a.consciousness!.letter);
      if (conscScore == 3) {
        reasons.add('Consciousness: ${a.consciousness!.label}.');
      }
    }

    final missing = <String>[
      if (rr == null) 'respiratory rate',
      if (sbp == null) 'systolic BP',
      if (hr == null) 'heart rate',
      if (!hasConsc) 'consciousness',
    ];
    final hasMissingVitals = missing.isNotEmpty || spo2Missing || tempMissing;

    final aggregate = (rrScore ?? 0) +
        (spo2Score ?? 0) +
        (sbpScore ?? 0) +
        (hrScore ?? 0) +
        (tempScore ?? 0) +
        o2Score +
        (conscScore ?? 0);

    final anyParamThree = rrScore == 3 ||
        spo2Score == 3 ||
        sbpScore == 3 ||
        hrScore == 3 ||
        tempScore == 3 ||
        conscScore == 3;

    var tier = _tierFromNews2(aggregate, anyParamThree);
    final review = hasMissingVitals;
    if (hasMissingVitals) {
      tier = tier.atMostUrgent(_missingVitalsFloor);
    }

    return _VitalOutcome(score: aggregate, tier: tier, review: review);
  }

  static TriageTier _tierFromNews2(int aggregate, bool anyParamThree) {
    if (aggregate >= 7 || anyParamThree) return TriageTier.p1;
    if (aggregate >= 5) return TriageTier.p2;
    if (aggregate >= 3) return TriageTier.p3;
    if (aggregate >= 1) return TriageTier.p4;
    return TriageTier.p5;
  }

  // ---- Peds-NEWS2 (spec §5.2) -----------------------------------------

  static _VitalOutcome _scorePeds(
      TriageAnswers a, AgeGroup age, List<String> reasons) {
    final bracket = age.pedsBracket!;
    final rr = _valueOf(a, 'rr');
    final sbp = _valueOf(a, 'sbp');
    final hr = _valueOf(a, 'hr');
    final hasConsc = a.consciousness != null;
    final hasRefill = a.capillaryRefill != null;

    int? rrScore;
    if (rr != null) {
      rrScore = PedsNews2Thresholds.respiratoryRateScore(bracket, rr);
      _noteThree(reasons, 'Respiratory rate', rr, rrScore);
    }

    int? sbpScore;
    if (sbp != null) {
      sbpScore = PedsNews2Thresholds.systolicBpScore(bracket, sbp);
      _noteThree(reasons, 'Systolic BP', sbp, sbpScore);
    } else {
      // ADR-013: BP is optional for the pediatric walkthrough (low-resource
      // field may lack a child cuff); informational only, never a review flag.
      reasons.add(
          'Blood pressure not measured (optional for this age group).');
    }

    int? hrScore;
    if (hr != null) {
      hrScore = PedsNews2Thresholds.heartRateScore(bracket, hr);
      _noteThree(reasons, 'Heart rate', hr, hrScore);
    }

    final spo2Missing = _isMissingSpo2(a);
    int? spo2Score;
    if (!spo2Missing) {
      spo2Score = PedsNews2Thresholds.spO2Score(a.spo2!);
      _noteThree(reasons, 'SpO2', a.spo2!, spo2Score);
    } else if (_respiratoryConcern(a, age)) {
      spo2Score = 3;
      reasons.add(
          'SpO2 not measured with a breathing concern - treated as severe.');
    } else {
      reasons.add('SpO2 not measured.');
    }

    final tempMissing = _isMissingTemp(a);
    int? tempScore;
    if (!tempMissing) {
      tempScore = PedsNews2Thresholds.temperatureScore(a.temperature!);
      _noteThree(reasons, 'Temperature', a.temperature!, tempScore);
    } else if (_temperatureConcern(a, age)) {
      tempScore = 2;
      reasons.add(
          'Temperature not measured with a fever concern - treated as raised.');
    } else {
      reasons.add('Temperature not measured.');
    }

    int? conscScore;
    if (hasConsc) {
      conscScore =
          News2Thresholds.avpuConsciousnessScore(a.consciousness!.letter);
      if (conscScore == 3) {
        reasons.add('Consciousness: ${a.consciousness!.label}.');
      }
    }

    int? refillScore;
    if (hasRefill) {
      refillScore = a.capillaryRefill!.score;
      if (refillScore == 3) {
        reasons.add('Capillary refill more than 3 seconds (3 points).');
      }
    }

    final missing = <String>[
      if (rr == null) 'respiratory rate',
      if (hr == null) 'heart rate',
      if (!hasConsc) 'consciousness',
      if (!hasRefill) 'capillary refill',
    ];
    final hasMissingVitals = missing.isNotEmpty || spo2Missing || tempMissing;

    final aggregate = (rrScore ?? 0) +
        (spo2Score ?? 0) +
        (sbpScore ?? 0) +
        (hrScore ?? 0) +
        (tempScore ?? 0) +
        (conscScore ?? 0) +
        (refillScore ?? 0);

    final anyParamThree = rrScore == 3 ||
        spo2Score == 3 ||
        sbpScore == 3 ||
        hrScore == 3 ||
        tempScore == 3 ||
        conscScore == 3 ||
        refillScore == 3;

    var tier = _tierFromNews2(aggregate, anyParamThree);
    final review = hasMissingVitals;
    if (hasMissingVitals) {
      tier = tier.atMostUrgent(_missingVitalsFloor);
    }

    return _VitalOutcome(score: aggregate, tier: tier, review: review);
  }

  // ---- Neonatal PEWS (spec §5.3) ---------------------------------------

  static _VitalOutcome _scorePews(
      TriageAnswers a, AgeGroup age, List<String> reasons) {
    final rr = _valueOf(a, 'rr');
    final hr = _valueOf(a, 'hr');
    final sbp = _valueOf(a, 'sbp');
    final hasConsc = a.neonatalConsciousness != null;

    final spo2Missing = _isMissingSpo2(a);
    final tempMissing = _isMissingTemp(a);

    int? rrScore;
    if (rr != null) rrScore = NeonatalPewsThresholds.respiratoryRateScore(rr);

    int? hrScore;
    if (hr != null) hrScore = NeonatalPewsThresholds.heartRateScore(hr);

    int? sbpScore;
    if (sbp != null) {
      sbpScore = NeonatalPewsThresholds.systolicBpScore(sbp);
    } else {
      // ADR-013: BP is optional for the neonatal walkthrough (low-resource
      // field may lack a neonate cuff); informational only, never a review flag.
      reasons.add(
          'Blood pressure not measured (optional for this age group).');
    }

    int? spo2Score;
    if (!spo2Missing) spo2Score = NeonatalPewsThresholds.spO2Score(a.spo2!);

    int? tempScore;
    if (!tempMissing) {
      tempScore = NeonatalPewsThresholds.temperatureScore(a.temperature!);
    }

    int? conscScore;
    if (hasConsc) {
      conscScore = NeonatalPewsThresholds.consciousnessScore(
          a.neonatalConsciousness!.stateKey);
      if (conscScore >= 2) {
        reasons.add(
            'Unresponsive, not feeding ($conscScore points).');
      }
    }

    if (spo2Missing) reasons.add('SpO2 not measured.');
    if (tempMissing) reasons.add('Temperature not measured.');

    final missing = <String>[
      if (rr == null) 'respiratory rate',
      if (hr == null) 'heart rate',
      if (!hasConsc) 'consciousness',
    ];
    final hasMissingVitals = missing.isNotEmpty || spo2Missing || tempMissing;

    final aggregate = (rrScore ?? 0) +
        (hrScore ?? 0) +
        (sbpScore ?? 0) +
        (spo2Score ?? 0) +
        (tempScore ?? 0) +
        (conscScore ?? 0);

    var tier = _tierFromUrgency(NeonatalPewsThresholds.tierUrgency(aggregate));
    final review = hasMissingVitals;
    if (hasMissingVitals) {
      // §21.4 rule 4: neonate + missing vitals -> P3 (overrides P4-by-age).
      tier = tier.atMostUrgent(_missingVitalsFloor);
    }

    return _VitalOutcome(score: aggregate, tier: tier, review: review);
  }

  static void _noteThree(
      List<String> reasons, String label, double value, int? score) {
    if (score == null || score < 3) return;
    final display =
        value == value.roundToDouble() ? value.toInt().toString() : '$value';
    reasons.add('$label $display scoring 3 points.');
  }

  // ---------------------------------------------------------------------
  // Chief complaint probing (§7/§8)
  // ---------------------------------------------------------------------

  /// Returns the escalation tier (if any) from the complaint probe score.
  /// Unanswered probes do not count, so a missing probe never escalates.
  static ({TriageTier? tier, int score}) _complaintTier(TriageAnswers a) {
    final branch = a.chiefComplaint?.branch;
    final questions = probeQuestions(branch);
    if (questions.isEmpty) return (tier: null, score: 0);

    var score = 0;
    for (final q in questions) {
      if (_probeConcerns(a, q)) score += q.score;
    }

    // E-C4: tearing back pain -> P1 regardless of any other score.
    if (branch == ProbeBranch.chest && (a.probeAnswers['E-C4'] ?? false)) {
      return (tier: TriageTier.p1, score: score);
    }

    final TriageTier? tier = switch (branch) {
      ProbeBranch.chest => score >= 6
          ? TriageTier.p1
          : score >= 4
              ? TriageTier.p2
              : null,
      ProbeBranch.breathing => score >= 6
          ? TriageTier.p1
          : score >= 3
              ? TriageTier.p2
              : null,
      ProbeBranch.fever => score >= 5
          ? TriageTier.p1
          : score >= 3
              ? TriageTier.p2
              : null,
      ProbeBranch.headache => score >= 5
          ? TriageTier.p1
          : score >= 3
              ? TriageTier.p2
              : null,
      ProbeBranch.abdo => score >= 5
          ? TriageTier.p1
          : score >= 3
              ? TriageTier.p2
              : null,
      ProbeBranch.psych => score >= 6
          ? TriageTier.p1
          : score >= 3
              ? TriageTier.p2
              : null,
      null => null,
    };

    return (tier: tier, score: score);
  }

  /// Whether a Yes (or, for inverted questions, a No) answer means "concern
  /// confirmed" for a probe.
  static bool _probeConcerns(TriageAnswers a, ProbeQuestion q) {
    if (q.id == 'E-B1') return a.probeAnswers[q.id] == false;
    return a.probeAnswers[q.id] ?? false;
  }

  // ---------------------------------------------------------------------
  // Sepsis screen (§9)
  // ---------------------------------------------------------------------

  static ({TriageTier? tier, String? reason}) _sepsisTier(TriageAnswers a) {
    final s = a.sepsis;
    final age = a.ageGroup;
    if (age == null) return (tier: null, reason: null);

    if (age.scale == VitalScale.news2) {
      // qSOFA (adult): altered mental status + RR>=22 + SBP<=100.
      final q = s.qsofa;
      if (q >= 2) {
        return (
          tier: TriageTier.p1,
          reason: 'Sepsis screen: qSOFA $q → immediate care',
        );
      }
      if (q == 1) {
        return (
          tier: TriageTier.p2,
          reason: 'Sepsis screen: qSOFA $q → possible sepsis',
        );
      }
      return (tier: null, reason: null);
    }

    if (age.scale == VitalScale.pedsNews2) {
      // pedSIRS (1-15y): temp/HR/RR criteria. Measured vitals win over the
      // F-screen answers when present; WBC criterion is skipped (no labs).
      final bracket = age.pedsBracket;
      var q = 0;

      final temp = _valueOf(a, 'temp');
      final tempAbn = temp != null
          ? (temp < 36.0 || temp > 38.5)
          : (s.f7 ?? false);
      if (tempAbn) q++;

      final rr = _valueOf(a, 'rr');
      final rrAbn = rr != null
          ? rr > PedsNews2Thresholds.respiratoryRate95th(bracket ?? 'teen')
          : (s.f3 ?? false);
      if (rrAbn) q++;

      final hr = _valueOf(a, 'hr');
      if (hr != null &&
          hr > PedsNews2Thresholds.heartRate95th(bracket ?? 'teen')) {
        q++;
      }

      if (q >= 2) {
        return (
          tier: TriageTier.p1,
          reason: 'Sepsis screen: pedSIRS $q (with suspected infection) → '
              'pediatric sepsis',
        );
      }
      if (q == 1) {
        return (
          tier: TriageTier.p2,
          reason: 'Sepsis screen: pedSIRS $q (with suspected infection) → '
              'possible sepsis',
        );
      }
      return (tier: null, reason: null);
    }

    // Neonates: sepsis handled by danger gates / clinical judgement.
    return (tier: null, reason: null);
  }
}

class _VitalOutcome {
  const _VitalOutcome({required this.score, required this.tier, required this.review});

  final int score;
  final TriageTier tier;

  /// True when any vital is missing/invalid (spec §21 rule 5).
  final bool review;
}
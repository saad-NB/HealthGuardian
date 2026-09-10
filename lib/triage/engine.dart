import '../config/clinical_thresholds.dart';
import 'models.dart';
import 'probes.dart';
import 'record.dart';

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
  static TriageResult compute(TriageAnswers a) => _evaluate(a).result;

  /// Full structured record (spec §15/§21.9) for persistence and sharing.
  static TriageRecord computeRecord(TriageAnswers a) => _evaluate(a).record;

  static ({TriageResult result, TriageRecord record}) _evaluate(
      TriageAnswers a) {
    final age = a.ageGroup;
    if (age == null) {
      const reasons = ['Age was not selected.'];
      final result = TriageResult(
        tier: _missingVitalsFloor,
        reasons: reasons,
        vitalReviewRequired: true,
      );
      return (
        result: result,
        record: _dangerRecord(a, result,
            safety: const ['ageMissing', 'vitalReviewRequired']),
      );
    }

    final reasons = <String>[];
    var tier = _applyDangerGates(a, reasons);

    if (tier == TriageTier.p1) {
      final result = TriageResult(
        tier: TriageTier.p1,
        reasons: reasons,
        scale: age.scale,
        vitalReviewRequired: false,
      );
      return (
        result: result,
        record: _dangerRecord(a, result,
            gates: {'passed': false, 'triggered': a.dangerSigns.toList()}),
      );
    }

    // === VITAL SIGNS (scale per §3 bracket) ===
    final vital = _vitalOutcome(a, age, reasons);
    tier = tier.atMostUrgent(vital.tier);
    reasons.add('${age.scale.label} score: ${vital.score}');

    // === CONSCIOUSNESS / GCS (§6) — only when all components collected ===
    final gcsTotal = _gcsTotal(a);
    var gcsTier = tier;
    if (gcsTotal != null) {
      gcsTier = _tierFromUrgency(GcsThresholds.tierFromGcs(
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
          'Complaint: ${complaint.label ?? '?'} → ${complaint.tier!.label}');
    }

    // === SEPSIS SCREEN (§9) ===
    final sepsis = _sepsisTier(a);
    final sepsisReason = sepsis.reason;
    if (sepsis.tier != null && sepsisReason != null) {
      tier = tier.atMostUrgent(sepsis.tier!);
      reasons.add(sepsisReason);
    }

    // === BURN MODULE (§11/§22) ===
    final burn = _burnTier(a);
    final burnReason = burn.reason;
    if (burn.tier != null && burnReason != null) {
      tier = tier.atMostUrgent(burn.tier!);
      reasons.add(burnReason);
    }

    // === MODIFIER BUMP AFTER MERGE (§12/§13 step 10) ===
    final vulnerableAge = _vulnerableAge(a);
    final activeModifiers = _activeModifiers(a, vulnerableAge);
    var bumpApplied = false;
    if (activeModifiers.isNotEmpty && tier != TriageTier.p1) {
      final preBump = tier;
      tier = tier.bumpOnce();
      bumpApplied = true;
      reasons.add(
          'Modifier bump: ${preBump.label} → ${tier.label} '
          '(${activeModifiers.join(', ')})');
    }

    final result = TriageResult(
      tier: tier,
      reasons: reasons,
      aggregate: vital.score,
      scale: age.scale,
      vitalReviewRequired: vital.review,
    );

    final record = _fullRecord(
      a,
      result,
      vital: vital,
      gcsTotal: gcsTotal,
      complaintScore: complaint.score,
      complaintTier: complaint.tier,
      sepsis: sepsis,
      burn: burn,
      vulnerableAge: vulnerableAge,
      activeModifiers: activeModifiers,
      bumpApplied: bumpApplied,
    );

    return (result: result, record: record);
  }

  static TriageRecord _dangerRecord(
    TriageAnswers a,
    TriageResult result, {
    Map<String, dynamic>? gates,
    List<String>? safety,
  }) {
    return TriageRecord.fromAnswers(
      answers: a,
      finalTier: result.tier,
      contributingScores: const {'gate': {'tier': 'P1', 'triggered': []}},
      mergeReasons: result.reasons,
      missingParams: const [],
      substitutionApplied: false,
      safetyFlags: safety ?? ['vitalReviewRequired'],
      modifiers: _modifiersBlock(a, false, true, const []),
      gates: gates ?? {'passed': true, 'triggered': []},
      inputs: _inputsSnapshot(a),
    );
  }

  static TriageRecord _fullRecord(
    TriageAnswers a,
    TriageResult result, {
    required _VitalOutcome vital,
    required int? gcsTotal,
    required int complaintScore,
    required TriageTier? complaintTier,
    required ({TriageTier? tier, String? reason}) sepsis,
    required ({TriageTier? tier, String? reason}) burn,
    required bool vulnerableAge,
    required List<String> activeModifiers,
    required bool bumpApplied,
  }) {
    final safety = <String>[
      if (vital.review) 'vitalReviewRequired',
    ];
    final contributing = <String, dynamic>{
      'vital': {
        if (result.scale != null) 'scale': result.scale!.name,
        'score': vital.score,
        'tier': vital.tier.label,
        'components': vital.components,
        'missingParams': vital.missing,
        'substitutionApplied': vital.substituted,
      },
      if (gcsTotal != null)
        'gcs': {'score': gcsTotal, 'tier': result.reasons.firstWhere(
          (r) => r.startsWith('GCS:'), orElse: () => 'GCS: $gcsTotal').split('→ ').last.trim()
        },
      if (a.chiefComplaint != null)
        'complaint': {
          'branch': a.chiefComplaint!.id,
          'score': complaintScore,
          'tier': complaintTier?.label,
        },
      if (sepsisReasonOf(result) != null)
        'sepsis': {'score': sepsisScoreOf(sepsis), 'tier': sepsis.tier?.label},
      if (burn.tier != null)
        'burn': {
          'cause': a.burn.cause?.name,
          'tbsa': a.burn.tbsaPercent,
          'depth': a.burn.depth?.label,
          'tier': burn.tier!.label,
          'reason': burn.reason,
        },
      'skin': null,
    };

    return TriageRecord.fromAnswers(
      answers: a,
      finalTier: result.tier,
      contributingScores: contributing,
      mergeReasons: result.reasons,
      missingParams: vital.missing,
      substitutionApplied: vital.substituted.isNotEmpty,
      safetyFlags: safety,
      modifiers:
          _modifiersBlock(a, vulnerableAge, bumpApplied, activeModifiers),
      gates: {'passed': a.dangerSigns.isEmpty, 'triggered': a.dangerSigns.toList()},
      inputs: _inputsSnapshot(a),
    );
  }

  static String? sepsisReasonOf(TriageResult result) {
    for (final r in result.reasons) {
      if (r.startsWith('Sepsis screen:')) return r;
    }
    return null;
  }

  static int sepsisScoreOf(
      ({TriageTier? tier, String? reason}) sepsis) {
    final reason = sepsis.reason ?? '';
    final m = RegExp(r'(qSOFA|pedSIRS) (\d)').firstMatch(reason);
    return m == null ? 0 : int.parse(m.group(2)!);
  }

  static Map<String, dynamic> _modifiersBlock(
    TriageAnswers a,
    bool vulnerableAge,
    bool bumpApplied,
    List<String> activeModifiers,
  ) {
    return {
      'ageVulnerable': vulnerableAge,
      'active': activeModifiers,
      'bumpApplied': bumpApplied,
      'ageYears': a.modifiers.ageYears,
      'pregnant': a.modifiers.pregnant,
      'immunocompromised': a.modifiers.immunocompromised,
      'muacCm': a.modifiers.muacCm,
      'cfsLevel': a.modifiers.cfsLevel,
    };
  }

  static Map<String, dynamic> _inputsSnapshot(TriageAnswers a) {
    return {
      'patientName': a.patientName,
      'age': a.ageGroup?.name,
      'ageYears': a.modifiers.ageYears,
      'vitals': {
        'rr': a.respiratoryRate,
        'spo2': a.spo2,
        'spo2Missing': a.spo2Missing,
        'sbp': a.systolicBp,
        'hr': a.heartRate,
        'temp': a.temperature,
        'tempMissing': a.tempMissing,
        'consciousness': a.consciousness?.letter,
        'capillaryRefill': a.capillaryRefill?.name,
        'neonatalConsciousness': a.neonatalConsciousness?.stateKey,
        'onOxygen': a.onOxygen,
        'copdCo2Retention': a.copdCo2Retention,
      },
      'gcs': [a.gcsEye, a.gcsVerbal, a.gcsMotor],
      'complaint': a.chiefComplaint?.id,
      'additionalComplaints':
          a.additionalComplaints.map((c) => c.id).toList(),
      'extraComplaintNotes': a.extraComplaintNotes,
      'probes': Map<String, bool>.from(a.probeAnswers),
      'burn': {
        'cause': a.burn.cause?.name,
        'timeframe': a.burn.timeSinceInjury?.name,
        'areas': a.burn.areas.map((x) => x.name).toList(),
        'shaded': a.burn.shaded
            .map((e) => '${e.$1.name}:${e.$2.name}')
            .toList(),
        'tbsa': a.burn.tbsaPercent,
        'depth': a.burn.depth?.name,
        'airwaySigns': a.burn.airwaySigns,
        'circumferential': a.burn.circumferential,
        'chemicalElectricalCriticalSite': a.burn.chemicalElectricalCriticalSite,
        'contaminated': a.burn.contaminated,
      },
      'modifiers': {
        'ageYears': a.modifiers.ageYears,
        'sex': a.modifiers.sex,
        'pregnant': a.modifiers.pregnant,
        'immunocompromised': a.modifiers.immunocompromised,
        'muacCm': a.modifiers.muacCm,
        'cfsLevel': a.modifiers.cfsLevel,
      },
    };
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

    if (spo2Missing) missing.add('spo2');
    if (tempMissing) missing.add('temperature');

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

    final substituted = <String, int>{};
    if (spo2Missing && spo2Score != null) substituted['spo2'] = spo2Score;
    if (tempMissing && tempScore != null) substituted['temperature'] = tempScore;

    return _VitalOutcome(
      score: aggregate,
      tier: tier,
      review: review,
      components: {
        'rr': ?rrScore,
        'spo2': ?spo2Score,
        'sbp': ?sbpScore,
        'hr': ?hrScore,
        'temp': ?tempScore,
        'avpu': ?conscScore,
        'o2': o2Score,
      },
      missing: missing,
      substituted: substituted,
    );
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

    if (spo2Missing) missing.add('spo2');
    if (tempMissing) missing.add('temperature');

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

    final substituted = <String, int>{};
    if (spo2Missing && spo2Score != null) substituted['spo2'] = spo2Score;
    if (tempMissing && tempScore != null) substituted['temperature'] = tempScore;

    return _VitalOutcome(
      score: aggregate,
      tier: tier,
      review: review,
      components: {
        'rr': ?rrScore,
        'spo2': ?spo2Score,
        'sbp': ?sbpScore,
        'hr': ?hrScore,
        'temp': ?tempScore,
        'avpu': ?conscScore,
        'capRefill': ?refillScore,
      },
      missing: missing,
      substituted: substituted,
    );
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

    if (spo2Missing) missing.add('spo2');
    if (tempMissing) missing.add('temperature');

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

    final substituted = <String, int>{};
    if (spo2Missing && spo2Score != null) substituted['spo2'] = spo2Score;
    if (tempMissing && tempScore != null) substituted['temperature'] = tempScore;

    return _VitalOutcome(
      score: aggregate,
      tier: tier,
      review: review,
      components: {
        'rr': ?rrScore,
        'hr': ?hrScore,
        'sbp': ?sbpScore,
        'spo2': ?spo2Score,
        'temp': ?tempScore,
        'consciousness': ?conscScore,
      },
      missing: missing,
      substituted: substituted,
    );
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

  /// Returns the most urgent escalation tier (if any) across every answered
  /// complaint (primary + additional), plus the winning complaint's label.
  /// Unanswered probes do not count, so a missing probe never escalates.
  static ({TriageTier? tier, int score, String? label}) _complaintTier(
      TriageAnswers a) {
    var best = (tier: null as TriageTier?, score: 0, label: null as String?);

    for (final complaint in a.answeredComplaints) {
      final branch = complaint.branch;
      final questions = probeQuestions(branch);
      if (questions.isEmpty) continue;

      var score = 0;
      for (final q in questions) {
        if (_probeConcerns(a, q)) score += q.score;
      }

      TriageTier? tier;
      // E-C4: tearing back pain -> P1 regardless of any other score.
      if (branch == ProbeBranch.chest && (a.probeAnswers['E-C4'] ?? false)) {
        tier = TriageTier.p1;
      } else {
        tier = switch (branch) {
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
      }

      if (tier != null &&
          (best.tier == null || tier.urgencyIndex < best.tier!.urgencyIndex)) {
        best = (tier: tier, score: score, label: complaint.label);
      }
    }

    return best;
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

  // ---------------------------------------------------------------------
  // Burn module (§11 H1-H8 + operative §22 decision table)
  // ---------------------------------------------------------------------

  /// Non-null when the burn module is engaged and produced a tier.
  /// Rule order matches the priority order of §22.9 (first match wins).
  static ({TriageTier? tier, String? reason}) _burnTier(TriageAnswers a) {
    final b = a.burn;
    final age = a.ageGroup;
    if (age == null) return (tier: null, reason: null);
    // Engaged via shading may carry TBSA with no critical BurnArea yet
    // (e.g. a plain arm segment), so engage when either is present.
    if (!b.engaged || (b.areas.isEmpty && b.tbsaPercent <= 0)) {
      return (tier: null, reason: null);
    }

    final isChild = age.scale != VitalScale.news2;
    final fullThickness = b.depth == BurnDepth.full;
    // §22.12 fail-closed: depth unsure → deep-partial.
    final deepPartial = b.depth == BurnDepth.deepPartial || b.depth == BurnDepth.unsure;
    final superficial = b.depth == BurnDepth.superficial;
    final partial = b.depth == BurnDepth.partial;
    final tbsa = b.tbsaPercent;

    // Rule 1: any airway sign → P1.
    if (b.airwaySigns) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: airway sign → immediate care',
      );
    }

    // Rule 2: chemical or electrical cause → P1 (hidden internal injury).
    if (b.cause?.isChemicalOrElectrical ?? false) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: chemical/electrical cause → immediate care',
      );
    }

    // Rule 3: full-thickness on a critical area → P1.
    if (fullThickness && b.hasCriticalArea) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: full-thickness on face/hands/feet/genitals/joint → '
            'immediate care',
      );
    }

    // Rule 4: circumferential full-thickness → P1.
    if (fullThickness && b.circumferential) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: circumferential full-thickness → immediate care',
      );
    }

    // Rule 18: circumferential full-thickness + abnormal distal pulse/refill.
    if (fullThickness && b.circumferential &&
        (a.capillaryRefill == CapillaryRefill.over3)) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: circumferential with poor distal circulation → '
            'immediate care',
      );
    }

    // Rule 19: face/genital burn with inhalational spread → P1.
    if ((b.areas.contains(BurnArea.face) ||
            b.areas.contains(BurnArea.genitals)) &&
        b.airwaySigns) {
      return (
        tier: TriageTier.p1,
        reason: 'Burn: face/genital with inhalation risk → immediate care',
      );
    }

    // Rule 5: TBSA ≥ 20% (adult) / ≥ 10% (child) → P2 (fluid threshold).
    final tbsaThreshold = isChild ? 10.0 : 20.0;
    if (tbsa >= tbsaThreshold) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: TBSA ≥ ${tbsaThreshold.toStringAsFixed(0)}% → '
            'fluid resuscitation threshold',
      );
    }

    // Rule 6: full-thickness > 1% any location → P2 (burn center).
    if (fullThickness && tbsa > 1) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: full-thickness > 1% → burn center',
      );
    }

    // Rule 7: critical area (face/hands/feet/genitals/joints) any depth → P2.
    if (b.hasCriticalArea) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: face/hands/feet/genitals/joint → functional risk',
      );
    }

    // Rule 8: deep-partial covering > 5% TBSA → P2 (excision threshold).
    if (deepPartial && tbsa > 5) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: deep partial > 5% → excision threshold',
      );
    }

    // Rule 9: circumferential non-full-thickness → P2 (compartment risk).
    if (b.circumferential) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: circumferential → compartment risk',
      );
    }

    // Rule 10: chemical/electrical to eyes/mouth/perineum → P2.
    if (b.chemicalElectricalCriticalSite) {
      return (
        tier: TriageTier.p2,
        reason: 'Burn: chemical/electrical to eye/mouth/perineum → '
            'critical structure',
      );
    }

    // Rule 15: contaminated burn → P3 (infection risk).
    if (b.contaminated) {
      return (
        tier: TriageTier.p3,
        reason: 'Burn: contaminated wound → infection risk',
      );
    }

    // Rule 16: immunocompromised + burn → P3.
    if (a.modifiers.immunocompromised == true) {
      return (
        tier: TriageTier.p3,
        reason: 'Burn: burn in an immunocompromised patient → infection risk',
      );
    }

    // Rule 11: partial scald/flame, TBSA 6-9% (child) / 11-19% (adult) → P3.
    final partialLow = isChild ? 6.0 : 11.0;
    final partialHigh = isChild ? 9.0 : 19.0;
    if (partial && tbsa >= partialLow && tbsa <= partialHigh) {
      return (
        tier: TriageTier.p3,
        reason: 'Burn: partial thickness $tbsa% → moderate burn',
      );
    }

    // Rule 12: partial-thickness, TBSA < 6% (child) / < 11% (adult),
    // single region, no risk areas → P4 (outpatient possible).
    if (partial && tbsa < partialLow && !b.hasCriticalArea) {
      return (
        tier: TriageTier.p4,
        reason: 'Burn: partial thickness $tbsa% no risk areas → outpatient',
      );
    }

    // Rule 13: deep-partial or full-thickness tiny (≤1%), no risk areas → P4.
    if ((deepPartial || fullThickness) && tbsa <= 1 && !b.hasCriticalArea) {
      return (
        tier: TriageTier.p4,
        reason: 'Burn: tiny deep burn (≤1%) → outpatient possible',
      );
    }

    // Rule 14: superficial only, TBSA ≤ 1%, no risk areas → P5 (self-care).
    if (superficial && tbsa <= 1 && !b.hasCriticalArea) {
      return (
        tier: TriageTier.p5,
        reason: 'Burn: superficial ≤1% → self-care',
      );
    }

    // Fail-closed default: an engaged but non-superficial burn we could not
    // safely classify stays at P3.
    return (
      tier: TriageTier.p3,
      reason: 'Burn: depth/area requires clinical review',
    );
  }

  // ---------------------------------------------------------------------
  // Modifiers (§12 I1-I7) and bump-after-merge (§13 step 10)
  // ---------------------------------------------------------------------

  /// True when the I1 age modifier triggers: the walkthrough uses age
  /// brackets (which already encode age-appropriate scales, ADR-013), so the
  /// bump only fires when the modifiers step records an explicit age that is
  /// outside the healthy-adult range (<5 or >65, spec �12 I1).
  static bool _vulnerableAge(TriageAnswers a) {
    final m = a.modifiers;
    if (m.ageYears == null) return false;
    return m.ageYears! < 5 || m.ageYears! > 65;
  }

  static List<String> _activeModifiers(TriageAnswers a, bool vulnerableAge) {
    final m = a.modifiers;
    final active = <String>[];
    if (vulnerableAge) {
      final years = m.ageYears;
      active.add(years != null && years < 5 ? 'Age <5' : 'Age >65');
    }
    if (m.pregnant == true) active.add('Pregnant');
    if (m.immunocompromised == true) active.add('Immunocompromised');
    if (m.muacCm != null && m.muacCm! < 11.5) {
      active.add('MUAC <11.5 cm');
    }
    if (m.cfsLevel != null && m.cfsLevel! >= 5) {
      active.add('CFS ${m.cfsLevel}');
    }
    return active;
  }
}

class _VitalOutcome {
  const _VitalOutcome({
    required this.score,
    required this.tier,
    required this.review,
    this.components = const {},
    this.missing = const [],
    this.substituted = const {},
  });

  final int score;
  final TriageTier tier;

  /// True when any vital is missing/invalid (spec §21 rule 5).
  final bool review;

  /// Per-parameter scores for the stored record (component -> score).
  final Map<String, int> components;

  /// Parameters that were missing/invalid this walkthrough.
  final List<String> missing;

  /// Substitutions applied for missing parameters (param -> substituted score).
  final Map<String, int> substituted;
}
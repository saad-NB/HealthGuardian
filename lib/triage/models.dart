import 'package:flutter/material.dart';

/// Age bracket chosen at the very first triage question.
/// Adult and OlderAdult both score with NEWS2 (adult table); infant/child use
/// a fail-closed safety path until Peds-NEWS2 / PEWS scales ship (see engine).
enum AgeGroup {
  infant(label: 'Infant', detail: '< 1 month'),
  child(label: 'Child', detail: '1 - 15 years'),
  adult(label: 'Adult', detail: '16+ years'),
  olderAdult(label: 'Older adult', detail: '65+ years');

  const AgeGroup({required this.label, required this.detail});

  final String label;
  final String detail;

  bool get usesNews2 => this == adult || this == olderAdult;
}

/// AVPU consciousness level (Section B7).
enum Avpu {
  alert(letter: 'A', label: 'Alert', detail: 'Awake and responsive'),
  voice(letter: 'V', label: 'Voice', detail: 'Responds to voice'),
  pain(letter: 'P', label: 'Pain', detail: 'Responds to pain only'),
  unresponsive(letter: 'U', label: 'Unresponsive', detail: 'No response');

  const Avpu({required this.letter, required this.label, required this.detail});

  final String letter;
  final String label;
  final String detail;
}

/// Five-tier triage outcome (spec §14).
enum TriageTier {
  p1(
    label: 'P1 - Emergency',
    shortLabel: 'Emergency',
    color: Color(0xFFD32F2F),
    response: 'Immediate',
    actionSteps: [
      'Call 112 or ambulance right now.',
      'Go to the nearest hospital now.',
      'Show this result to the ambulance or hospital team.',
    ],
  ),
  p2(
    label: 'P2 - Very Urgent',
    shortLabel: 'Very Urgent',
    color: Color(0xFFF57C00),
    response: 'Within 10 minutes',
    actionSteps: [
      'Contact a doctor or go to hospital without delay.',
      'Someone should stay with the patient.',
      'Recheck in 10 minutes; go sooner if they worsen.',
    ],
  ),
  p3(
    label: 'P3 - Urgent',
    shortLabel: 'Urgent',
    color: Color(0xFFFBC02D),
    response: '30 - 60 minutes',
    useDarkText: true,
    actionSteps: [
      'See a doctor today.',
      'Recheck symptoms in 30 minutes.',
      'Go to hospital if anything becomes severe.',
    ],
  ),
  p4(
    label: 'P4 - Standard',
    shortLabel: 'Standard',
    color: Color(0xFF388E3C),
    response: 'Within 2 hours',
    actionSteps: [
      'Arrange a routine check-up.',
      'Recheck symptoms in 2 hours.',
      'Return for triage if symptoms change.',
    ],
  ),
  p5(
    label: 'P5 - Minor',
    shortLabel: 'Minor',
    color: Color(0xFF1976D2),
    response: 'Within 4 hours',
    actionSteps: [
      'Care at home is usually enough.',
      'Recheck symptoms in 4 hours.',
      'Return for triage or see a doctor if anything changes.',
    ],
  );

  const TriageTier({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.response,
    required this.actionSteps,
    this.useDarkText = false,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final String response;
  final bool useDarkText;
  final List<String> actionSteps;

  int get urgencyIndex => index;

  /// The more urgent of [this] and [other] (P1 is index 0).
  TriageTier atMostUrgent(TriageTier other) =>
      urgencyIndex <= other.urgencyIndex ? this : other;
}

/// One collected triage session (Sections A/B only for this increment).
class TriageAnswers {
  AgeGroup? ageGroup;
  final Set<String> dangerSigns = {};

  double? respiratoryRate;
  double? spo2;
  double? systolicBp;
  double? heartRate;
  double? temperature;
  Avpu? consciousness;
  bool onOxygen = false;
  bool copdCo2Retention = false;

  /// Explicit "not available" markers so an unentered value can be told
  /// apart from an intentionally-missing one (spec §21).
  bool spo2Missing = false;
  bool tempMissing = false;

  void reset() {
    ageGroup = null;
    dangerSigns.clear();
    respiratoryRate = null;
    spo2 = null;
    systolicBp = null;
    heartRate = null;
    temperature = null;
    consciousness = null;
    onOxygen = false;
    copdCo2Retention = false;
    spo2Missing = false;
    tempMissing = false;
  }
}

/// Outcome of the Tier 1 engine, plus a human-readable reason string.
class TriageResult {
  const TriageResult({
    required this.tier,
    required this.reasons,
    required this.vitalReviewRequired,
    this.aggregate,
    this.decisionSupport = true,
  });

  final TriageTier tier;
  final List<String> reasons;
  final bool vitalReviewRequired;

  /// NEWS2 aggregate when an adult path was scored.
  final int? aggregate;

  /// Every result is framed as decision support, never a diagnosis.
  final bool decisionSupport;
}
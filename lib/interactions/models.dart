import 'package:flutter/foundation.dart';

/// Drug-drug interaction types (ADR-018, docs/DRUG_INTERACTIONS.md).
///
/// Pure data — no plugin/platform code, so the dataset and engine run headless
/// in unit tests.

/// Clinical urgency of a known interaction, ordered least → most urgent.
///
/// [reported] is the ungraded tier: the pair is on record in the source data
/// but the public dataset does not carry a severity. It is deliberately kept
/// below [moderate] and is never presented as "safe".
enum InteractionSeverity {
  reported(
    label: 'Reported',
    headline: 'Interaction on record',
    advice:
        'This pair is listed as an interaction, but its severity is not graded '
        'in the reference data. Ask a pharmacist before combining them.',
  ),
  moderate(
    label: 'Moderate',
    headline: 'Moderate interaction',
    advice:
        'Your doctor may want to monitor you or adjust the dose. Talk to a '
        'pharmacist before taking these together.',
  ),
  severe(
    label: 'Severe',
    headline: 'Serious interaction',
    advice:
        'This is a serious interaction. Talk to your doctor or pharmacist '
        'before taking these together.',
  ),
  contraindicated(
    label: 'Contraindicated',
    headline: 'Do not use together',
    advice:
        'These medicines are contraindicated together. Do not take them at the '
        'same time — ask your doctor about alternatives.',
  );

  const InteractionSeverity({
    required this.label,
    required this.headline,
    required this.advice,
  });

  final String label;
  final String headline;
  final String advice;

  /// Whether the UI must block with a warning popup rather than just list it.
  bool get blocks => this == severe || this == contraindicated;
}

/// A generic (ingredient-level) medicine name, optionally with its RxNorm code.
@immutable
class Drug {
  const Drug({required this.name, this.rxcui});

  final String name;
  final String? rxcui;
}

/// One matched interaction between two medicines the user entered.
@immutable
class DrugInteraction {
  const DrugInteraction({
    required this.drugA,
    required this.drugB,
    required this.severity,
  });

  final String drugA;
  final String drugB;
  final InteractionSeverity severity;
}

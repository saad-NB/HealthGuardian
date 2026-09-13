import 'dataset.dart';
import 'models.dart';

/// Checks a list of medicines for known interactions (ADR-018).
///
/// Pure and synchronous: all data comes from the already-loaded
/// [InteractionDataset], so the engine is trivial to unit-test.
class InteractionEngine {
  const InteractionEngine(this.dataset);

  final InteractionDataset dataset;

  /// Every interaction among [drugs], most urgent first.
  ///
  /// Duplicates (by normalized name) are collapsed, so entering "Warfarin" and
  /// "warfarin" is treated as one medicine.
  List<DrugInteraction> check(List<String> drugs) {
    final unique = <String>[];
    final seen = <String>{};
    for (final drug in drugs) {
      final key = normalizeDrugName(drug);
      if (key.isEmpty || !seen.add(key)) continue;
      unique.add(drug);
    }

    final results = <DrugInteraction>[];
    for (var i = 0; i < unique.length; i++) {
      for (var j = i + 1; j < unique.length; j++) {
        final severity = dataset.severityFor(unique[i], unique[j]);
        if (severity == null) continue;
        results.add(
          DrugInteraction(
            drugA: unique[i],
            drugB: unique[j],
            severity: severity,
          ),
        );
      }
    }

    results.sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      if (bySeverity != 0) return bySeverity;
      return a.drugA.compareTo(b.drugA);
    });
    return results;
  }

  /// Entered names that are not in the reference data, in input order.
  List<String> unknownDrugs(List<String> drugs) {
    final unknown = <String>[];
    final seen = <String>{};
    for (final drug in drugs) {
      if (drug.trim().isEmpty) continue;
      if (!seen.add(normalizeDrugName(drug))) continue;
      if (!dataset.isKnownDrug(drug)) unknown.add(drug);
    }
    return unknown;
  }

  /// True when at least one result warrants a blocking popup.
  bool hasBlocking(List<DrugInteraction> results) =>
      results.any((r) => r.severity.blocks);
}

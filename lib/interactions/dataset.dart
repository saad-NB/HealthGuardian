import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'models.dart';

/// Case/punctuation-insensitive key for a medicine name.
///
/// The bundled names are already clean display names ("Warfarin",
/// "Sodium Phosphate"); this collapses spacing and strips punctuation so user
/// input ("sodium  phosphate", "N,N-dimethyl…") matches the stored pair keys.
String normalizeDrugName(String value) {
  var text = value.toLowerCase().trim();
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _pairKey(String a, String b) => a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

/// Read-only drug-interaction reference data, loaded once from the bundled
/// JSON assets (`assets/data/ddi.json`, `assets/data/drug_names.json`).
///
/// The dataset is intentionally plain: a list of generic names for
/// autocomplete and a normalized pair → severity map for lookups.
class InteractionDataset {
  InteractionDataset._(this.drugs, this._pairs);

  final List<Drug> drugs;
  final Map<String, int> _pairs;

  static const String ddiAsset = 'assets/data/ddi.json';
  static const String namesAsset = 'assets/data/drug_names.json';

  int get drugCount => drugs.length;
  int get pairCount => _pairs.length;

  /// Load the bundled assets. [bundle] is injectable for tests.
  static Future<InteractionDataset> load({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    final ddi = jsonDecode(await source.loadString(ddiAsset));
    final names = jsonDecode(await source.loadString(namesAsset));
    return InteractionDataset.fromJson(
      (ddi as Map).cast<String, dynamic>(),
      (names as Map).cast<String, dynamic>(),
    );
  }

  /// Build from already-decoded JSON (used by [load] and by tests).
  factory InteractionDataset.fromJson(
    Map<String, dynamic> ddi,
    Map<String, dynamic> names,
  ) {
    final drugs = <Drug>[];
    for (final row in (names['names'] as List)) {
      final entry = row as List;
      final rxcui = entry[1] as String;
      drugs.add(
        Drug(name: entry[0] as String, rxcui: rxcui.isEmpty ? null : rxcui),
      );
    }

    final pairs = <String, int>{};
    for (final row in (ddi['pairs'] as List)) {
      final entry = row as List;
      final a = normalizeDrugName(entry[0] as String);
      final b = normalizeDrugName(entry[1] as String);
      final severity = (entry[2] as num).toInt();
      if (a.isEmpty || b.isEmpty || a == b) continue;
      pairs[_pairKey(a, b)] = severity;
    }

    return InteractionDataset._(drugs, pairs);
  }

  /// Severity for the unordered pair, or null when no interaction is known.
  InteractionSeverity? severityFor(String a, String b) {
    final index = _pairs[_pairKey(normalizeDrugName(a), normalizeDrugName(b))];
    if (index == null ||
        index < 0 ||
        index >= InteractionSeverity.values.length) {
      return null;
    }
    return InteractionSeverity.values[index];
  }

  /// Whether [name] exists in the reference data (for "unknown medicine" hints).
  bool isKnownDrug(String name) {
    final key = normalizeDrugName(name);
    if (key.isEmpty) return false;
    return _nameIndex.contains(key);
  }

  Set<String>? _nameIndexCache;
  Set<String> get _nameIndex =>
      _nameIndexCache ??= drugs.map((d) => normalizeDrugName(d.name)).toSet();

  /// Autocomplete: prefix matches first, then substring matches, alphabetical.
  List<Drug> search(String query, {int limit = 8}) {
    final q = normalizeDrugName(query);
    if (q.isEmpty) return const [];
    final prefix = <Drug>[];
    final contains = <Drug>[];
    for (final drug in drugs) {
      final name = normalizeDrugName(drug.name);
      if (name.startsWith(q)) {
        prefix.add(drug);
      } else if (name.contains(q)) {
        contains.add(drug);
      }
    }
    int byName(Drug a, Drug b) => a.name.compareTo(b.name);
    prefix.sort(byName);
    contains.sort(byName);
    return [...prefix, ...contains].take(limit).toList(growable: false);
  }
}

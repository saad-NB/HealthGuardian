import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// One completed interaction check, kept in the Drugs tab's history.
@immutable
class SavedDrugCheck {
  const SavedDrugCheck({
    required this.drugs,
    required this.checkedAt,
    required this.interactions,
  });

  final List<String> drugs;
  final DateTime checkedAt;
  final List<DrugInteraction> interactions;

  Map<String, dynamic> toJson() => {
        'drugs': drugs,
        'checkedAt': checkedAt.toIso8601String(),
        'interactions': [
          for (final i in interactions)
            {'a': i.drugA, 'b': i.drugB, 'severity': i.severity.name},
        ],
      };

  factory SavedDrugCheck.fromJson(Map<String, dynamic> json) => SavedDrugCheck(
        drugs: (json['drugs'] as List).map((e) => e as String).toList(),
        checkedAt: DateTime.parse(json['checkedAt'] as String),
        interactions: [
          for (final entry in (json['interactions'] as List? ?? const []))
            DrugInteraction(
              drugA: (entry as Map)['a'] as String,
              drugB: entry['b'] as String,
              severity: InteractionSeverity.values
                  .byName(entry['severity'] as String),
            ),
        ],
      );
}

/// Local store for saved interaction checks (mirrors `MonitorStore`).
///
/// Persists only the entered generic names, the matched severities, and the
/// timestamp — one small JSON file in the app directory, keeping the
/// offline-first, privacy-preserving posture.
class DrugCheckStore {
  DrugCheckStore({this.file});

  /// Override target for tests (real builds resolve the app-support dir).
  final File? file;

  static const String defaultFilename = 'drug_checks_v1.json';

  /// Newest-first checks already stored, or empty when nothing/corrupt exists.
  Future<List<SavedDrugCheck>> loadRecent() async {
    final target = await _resolve();
    if (!await target.exists()) return const [];
    try {
      final entries = jsonDecode(await target.readAsString()) as List;
      final checks = <SavedDrugCheck>[];
      for (final entry in entries) {
        try {
          checks.add(
            SavedDrugCheck.fromJson((entry as Map).cast<String, dynamic>()),
          );
        } catch (_) {
          // Skip a corrupt entry rather than failing the whole list.
        }
      }
      return checks;
    } catch (_) {
      return const [];
    }
  }

  /// Prepend a check (deduped by names + timestamp), capped at 20.
  Future<void> save(SavedDrugCheck check) async {
    final existing = await loadRecent();
    final updated = <SavedDrugCheck>[
      check,
      ...existing.where((c) => !_sameCheck(c, check)),
    ];
    final target = await _resolve();
    await target.writeAsString(
      jsonEncode(updated.take(20).map((c) => c.toJson()).toList()),
    );
  }

  Future<void> remove(SavedDrugCheck check) async {
    final existing = await loadRecent();
    final updated = existing.where((c) => !_sameCheck(c, check)).toList();
    final target = await _resolve();
    await target.writeAsString(
      jsonEncode(updated.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final target = await _resolve();
    if (await target.exists()) await target.delete();
  }

  Future<File> _resolve() async {
    final overridden = file;
    if (overridden != null) return overridden;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$defaultFilename');
  }

  static bool _sameCheck(SavedDrugCheck a, SavedDrugCheck b) =>
      a.checkedAt == b.checkedAt &&
      a.drugs.length == b.drugs.length &&
      _sameNames(a.drugs, b.drugs);

  static bool _sameNames(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].toLowerCase() != b[i].toLowerCase()) return false;
    }
    return true;
  }
}

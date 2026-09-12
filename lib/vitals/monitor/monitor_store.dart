import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Compact local store for accepted vitals readings (VITALS_SENSING §7.3).
///
/// Persists only the {kind, value, confidence, timestamp} snapshot — never raw
/// frames or audio — as one small JSON file in the app directory, keeping the
/// offline-first, privacy-preserving posture. Powers the Monitor tab's recent
/// readings list and the in-triage "use latest reading" offer.
class MonitorStore {
  MonitorStore({this.file});

  /// Override target for tests (real builds resolve the app-support dir).
  final File? file;

  static const String defaultFilename = 'monitor_readings_v1.json';

  /// Newest-first readings already stored, or the empty list when nothing (or
  /// only legacy/corrupt data) exists. Malformed entries are skipped rather
  /// than failing the whole list.
  Future<List<VitalReading>> loadRecent() async {
    final file = await _resolve();
    if (!await file.exists()) return const [];
    try {
      final entries = jsonDecode(await file.readAsString()) as List;
      final readings = <VitalReading>[];
      for (final entry in entries) {
        try {
          readings.add(
            VitalReading.fromJson((entry as Map).cast<String, dynamic>()),
          );
        } catch (_) {
          // Skip a corrupt entry rather than failing the whole list.
        }
      }
      return readings;
    } catch (_) {
      return const [];
    }
  }

  /// Prepend an accepted reading (deduped by kind + timestamp), capped at 50
  /// so the file stays small.
  Future<void> save(VitalReading reading) async {
    final existing = await loadRecent();
    final updated = <VitalReading>[
      reading,
      ...existing.where((r) => !_sameReading(r, reading)),
    ];
    final file = await _resolve();
    await file.writeAsString(
      jsonEncode(updated.take(50).map((r) => r.toJson()).toList()),
    );
  }

  /// Drop the stored reading that matches [reading] (kind + timestamp).
  Future<void> remove(VitalReading reading) async {
    final existing = await loadRecent();
    final updated = existing.where((r) => !_sameReading(r, reading)).toList();
    final file = await _resolve();
    await file.writeAsString(
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final file = await _resolve();
    if (await file.exists()) await file.delete();
  }

  Future<File> _resolve() async {
    final overridden = file;
    if (overridden != null) return overridden;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$defaultFilename');
  }

  static bool _sameReading(VitalReading a, VitalReading b) =>
      a.kind == b.kind && a.measuredAt == b.measuredAt;
}
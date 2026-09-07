import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'record.dart';

/// Encrypted local store for completed triage records (spec §15 / §19-2).
///
/// Records are keyed by [TriageRecord.triageId] under a single JSON index so
/// the History screen can list them newest-first without re-reading every
/// value. Storage uses the platform keystore (Keystore / Keychain) via
/// `flutter_secure_storage`.
class TriageRecordStore {
  TriageRecordStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _indexKey = 'triage_records_index_v1';
  static const String _keyPrefix = 'triage_record_';

  final FlutterSecureStorage _storage;

  /// Loads every stored record, newest first, by triageId timestamp.
  Future<List<TriageRecord>> loadAll() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null) return const [];
    final ids = (jsonDecode(raw) as List).cast<String>();
    final records = <TriageRecord>[];
    for (final id in ids) {
      final payload = await _storage.read(key: _keyPrefix + id);
      if (payload == null) continue;
      try {
        records.add(
          TriageRecord.fromJson(jsonDecode(payload) as Map<String, dynamic>),
        );
      } catch (_) {
        // Skip a corrupt entry rather than failing the whole list.
      }
    }
    return records;
  }

  /// Saves (or replaces, idempotent) one record and prepends the id to the
  /// index. Cap the list at 200 records to avoid unbounded keystore growth.
  Future<void> save(TriageRecord record) async {
    final encoded = jsonEncode(record.toJson());

    final existingRaw = await _storage.read(key: _indexKey);
    final existing = existingRaw == null
        ? <String>[]
        : (jsonDecode(existingRaw) as List).cast<String>();
    final updated = <String>[record.triageId, ...existing.where((id) => id != record.triageId)];

    await _storage.write(key: _keyPrefix + record.triageId, value: encoded);
    await _storage.write(
      key: _indexKey,
      value: jsonEncode(updated.take(200).toList(growable: false)),
    );
  }

  /// Deletes one record by id and removes it from the index.
  Future<void> delete(String triageId) async {
    await _storage.delete(key: _keyPrefix + triageId);
    final raw = await _storage.read(key: _indexKey);
    if (raw == null) return;
    final ids = (jsonDecode(raw) as List)
        .cast<String>()
        .where((id) => id != triageId)
        .toList(growable: false);
    await _storage.write(key: _indexKey, value: jsonEncode(ids));
  }

  Future<void> clearAll() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw != null) {
      for (final id in (jsonDecode(raw) as List).cast<String>()) {
        await _storage.delete(key: _keyPrefix + id);
      }
    }
    await _storage.delete(key: _indexKey);
  }
}
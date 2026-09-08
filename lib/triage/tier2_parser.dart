import 'dart:convert';

import 'models.dart';
import 'tier2.dart';

/// Tolerant parser for MedGemma's structured Tier 2 reply (ADR-014).
///
/// fllama exposes no GBNF grammar constraint, so the model is prompted to reply
/// with a single strict-JSON object. This parser extracts the first brace-
/// balanced object anywhere in the reply, decodes it leniently, validates the
/// tier, and **fails closed**: any hiccup yields `suggestion: null` so the AI
/// is ignored and Tier 1 stands. It never guesses an escalation.
class Tier2Parser {
  Tier2Parser._();

  static const List<String> _tierKeys = [
    'triage_level',
    'triageLevel',
    'tier',
    'triage',
    'priority',
  ];

  static const List<String> _summaryKeys = ['summary', 'explanation', 'note'];

  static Tier2Assessment parse(String raw) {
    if (raw.trim().isEmpty) return const Tier2Assessment();

    final decoded = _decodeFirstObject(raw);
    if (decoded == null) return const Tier2Assessment();

    final suggestion = _parseTier(decoded);
    final summary = _summaryKeys
        .map((k) => _stringValue(decoded[k]))
        .firstWhere((v) => v != null, orElse: () => null);
    final humanReview =
        _boolValue(decoded['requires_human_verification']) ?? true;

    return Tier2Assessment(
      suggestion: suggestion,
      summary: summary ?? '',
      requiresHumanVerification: humanReview,
      rawOutput: raw,
    );
  }

  static TriageTier? _parseTier(Map<String, dynamic> json) {
    for (final key in _tierKeys) {
      final value = json[key];
      if (value == null) continue;
      final tier = _coerceTier(value);
      if (tier != null) return tier;
    }
    return null;
  }

  static TriageTier? _coerceTier(dynamic value) {
    if (value is num) {
      return switch (value) {
        1 => TriageTier.p1,
        2 => TriageTier.p2,
        3 => TriageTier.p3,
        4 => TriageTier.p4,
        5 => TriageTier.p5,
        _ => null,
      };
    }
    if (value is String) {
      final s = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return switch (s) {
        'p1' || 'emergency' => TriageTier.p1,
        'p2' || 'veryurgent' => TriageTier.p2,
        'p3' || 'urgent' => TriageTier.p3,
        'p4' || 'standard' => TriageTier.p4,
        'p5' || 'minor' || 'routine' => TriageTier.p5,
        _ => null,
      };
    }
    return null;
  }

  static String? _stringValue(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return null;
  }

  static bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  /// Extracts and decodes the first brace-balanced JSON object in [raw].
  /// Returns null when no valid object can be found at the top level.
  static Map<String, dynamic>? _decodeFirstObject(String raw) {
    var start = -1;
    for (var i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == _open) {
        start = i;
        break;
      }
    }
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escape = false;
    var end = -1;
    for (var i = start; i < raw.length; i++) {
      final c = raw.codeUnitAt(i);
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == _escape) {
          escape = true;
        } else if (c == _quote) {
          inString = false;
        }
        continue;
      }
      if (c == _quote) {
        inString = true;
        continue;
      }
      if (c == _open) {
        depth++;
      } else if (c == _close) {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;

    final block = raw.substring(start, end + 1);
    try {
      final decoded = jsonDecode(block);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // fall through -> fail closed
    }
    return null;
  }

  static const int _open = 0x7B; // '{'
  static const int _close = 0x7D; // '}'
  static const int _quote = 0x22; // '"'
  static const int _escape = 0x5C; // '\'
}
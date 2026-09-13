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
    if (decoded == null) {
      // Strict JSON failed (e.g. unescaped newlines in the summary). Fall back
      // to tolerant regex extraction; any miss fails closed but keeps the raw
      // text so the reply is never silently lost. A leading visible "thought"
      // stanza is masked so its text can't pollute the regex keys.
      final safeRaw = _maskThoughtBlocks(raw);
      return Tier2Assessment(
        suggestion: _regexTier(safeRaw),
        summary: _regexText(safeRaw, _summaryKeys) ?? '',
        requiresHumanVerification: true,
        rawOutput: raw,
      );
    }

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

  /// True once [raw] already contains a complete brace-balanced JSON object that
  /// carries a triage or summary key. Used to cancel summary inference early so
  /// the model cannot over-generate past a valid answer.
  static bool hasCompleteObject(String raw) {
    if (raw.isEmpty || !raw.trimRight().endsWith('}')) return false;
    final decoded = _decodeFirstObject(raw);
    return decoded != null && _hasTierOrSummaryKey(decoded);
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

  /// Finds and decodes the best brace-balanced JSON object in [raw].
  ///
  /// MedGemma may emit a visible `{"thought": ...}` stanza before the real
  /// summary object, so this scans every balanced block in document order:
  /// the first block that decodes *and* carries a triage key or a summary key
  /// wins (skipping reasoning-only blocks); the first decodable block is kept
  /// as a last resort so a pure-thought reply still fails closed gracefully.
  /// Returns null when nothing decodes at all.
  static Map<String, dynamic>? _decodeFirstObject(String raw) {
    Map<String, dynamic>? firstDecodable;
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
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(_repairEscapes(block));
      if (value is Map<String, dynamic>) decoded = value;
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } catch (_) {
      // not a JSON object — keep scanning for a later block
    }
    if (decoded != null) {
      firstDecodable ??= decoded;
      // Reasoning-only blocks ({"thought": ...}) are skipped: keep scanning
      // for the real summary object that follows them.
      if (_hasTierOrSummaryKey(decoded)) return decoded;
    }

    // Multi-brace fallback: keep looking for a later object after this block.
    final rest = _decodeFirstObject(raw.substring(end + 1));
    return rest ?? firstDecodable;
  }

  static bool _hasTierOrSummaryKey(Map<String, dynamic> json) {
    for (final key in _tierKeys) {
      if (json.containsKey(key)) return true;
    }
    for (final key in _summaryKeys) {
      if (json.containsKey(key)) return true;
    }
    return false;
  }

  /// Returns [raw] with any leading block that is a reasoning-only JSON object
  /// (e.g. `{"thought": "..."}`) blanked out, so tolerant regex fallbacks don't
  /// read triage-ish words from the model's visible reasoning.
  static String _maskThoughtBlocks(String raw) {
    var start = -1;
    for (var i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == _open) {
        start = i;
        break;
      }
    }
    if (start < 0) return raw;

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
          i = raw.length;
        }
      }
    }
    if (end < 0) return raw;

    Map<String, dynamic>? decodedValue;
    try {
      final value = jsonDecode(_repairEscapes(raw.substring(start, end + 1)));
      if (value is Map<String, dynamic>) decodedValue = value;
      if (value is Map) decodedValue = Map<String, dynamic>.from(value);
    } catch (_) {
      return raw;
    }
    if (decodedValue == null || _hasTierOrSummaryKey(decodedValue)) return raw;

    // Blank the reasoning-only block (keeps offsets stable for regex).
    final sb = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      sb.write(i >= start && i <= end ? ' ' : raw[i]);
    }
    return sb.toString();
  }

  /// Makes raw newlines/tabs inside string values valid JSON escapes
  /// (MedGemma frequently emits literal line breaks inside `summary`).
  static String _repairEscapes(String block) {
    final sb = StringBuffer();
    var inString = false;
    var escape = false;
    for (var i = 0; i < block.length; i++) {
      final c = block[i];
      if (inString) {
        if (escape) {
          sb.write(c);
          escape = false;
        } else if (c == r'\') {
          sb.write(c);
          escape = true;
        } else if (c == '"') {
          sb.write(c);
          inString = false;
        } else if (c == '\n' || c == '\r') {
          sb.write(r'\n');
        } else if (c == '\t') {
          sb.write(r'\t');
        } else {
          sb.write(c);
        }
        continue;
      }
      if (c == '"') {
        sb.write(c);
        inString = true;
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  /// Last-resort field extraction from raw text when strict JSON decode fails.
  /// Uses the *last* key match: any stray key in a visible reasoning stanza
  /// precedes the final structured fragment the model must produce.
  static String? _regexText(String raw, List<String> keys) {
    for (final key in keys) {
      final matches =
          RegExp('"$key"\\s*:\\s*"([^"\\\\]|\\\\.)*"', caseSensitive: false)
              .allMatches(raw);
      Match? last;
      for (final m in matches) {
        last = m;
      }
      final m = last;
      if (m != null) {
        final full = m.group(0)!;
        final open = full.indexOf('"', full.indexOf(':'));
        final close = full.lastIndexOf('"');
        if (open >= 0 && close > open) {
          return full.substring(open + 1, close).trim();
        }
      }
    }
    return null;
  }

  static TriageTier? _regexTier(String raw) {
    for (final key in _tierKeys) {
      final matches =
          RegExp('"$key"\\s*:\\s*"([^"\\\\]|\\\\.)*"', caseSensitive: false)
              .allMatches(raw);
      Match? last;
      for (final m in matches) {
        last = m;
      }
      final m = last;
      if (m != null) {
        final full = m.group(0)!;
        final close = full.lastIndexOf('"');
        final open = full.indexOf('"', full.indexOf(':'));
        final value = open >= 0 && close > open
            ? full.substring(open + 1, close)
            : '';
        final tier = _coerceTier(value);
        if (tier != null) return tier;
      }
    }
    return null;
  }

  static const int _open = 0x7B; // '{'
  static const int _close = 0x7D; // '}'
  static const int _quote = 0x22; // '"'
  static const int _escape = 0x5C; // '\'
}
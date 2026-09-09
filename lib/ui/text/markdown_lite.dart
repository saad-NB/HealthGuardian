import 'package:flutter/painting.dart';

/// Minimal, dependency-free Markdown rendering for model text (ADR-014).
///
/// Supports the two structures the local model reliably emits — bullet lines
/// and **bold** / *italic* / `code` runs — without pulling in a full parser.
/// Anything unrecognized is passed through unchanged, so muscle-memory
/// markdown still degrades gracefully to plain text.
class MarkdownLite {
  MarkdownLite._();

  /// Inline delimiters: bold `**x**`, code `` `x` ``, then italic `*x*`.
  /// (Bold is matched first so `**x**` isn't eaten as two italics.)
  static final RegExp _inline = RegExp(r'(\*\*[^*]+\*\*|`[^`\n]+`|\*[^*\n]+\*)');

  /// A line opener that should render as a real bullet, e.g. `- `, `* ` or
  /// `1. ` (also `1)`), either as literal leading characters.
  static final RegExp _bullet = RegExp(r'^(\s*)(?:[-*]|\d+[.)])\s+');

  /// Renders [text] into rich inline spans. Lines starting with a list marker
  /// become `•`-prefixed with two-space padding; inline runs get styled via
  /// [style] (bold/italic/code, monospace for code).
  static List<TextSpan> buildSpans(String text, {required TextStyle style}) {
    final spans = <TextSpan>[];
    final lines = text.split('\n');
    for (var l = 0; l < lines.length; l++) {
      if (l > 0) spans.add(TextSpan(text: '\n'));
      final line = lines[l];
      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        final rest = line.substring(bullet.end);
        spans.add(TextSpan(text: '•  ', style: style));
        spans.addAll(_inlineSpans(rest, style));
      } else {
        spans.addAll(_inlineSpans(line, style));
      }
    }
    return spans;
  }

  /// Builds inline spans for a single (non-bulleted) run of text.
  static List<TextSpan> _inlineSpans(String source, TextStyle style) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(source)) {
      if (m.start > last) {
        _pushPlain(spans, source.substring(last, m.start), style);
      }
      final token = m[0]!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: style.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (token.startsWith('`')) {
        final color = style.color;
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: color?.withValues(alpha: 0.08),
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < source.length) {
      _pushPlain(spans, source.substring(last), style);
    }
    return spans;
  }

  static void _pushPlain(
    List<TextSpan> spans,
    String text,
    TextStyle style,
  ) {
    if (text.isNotEmpty) spans.add(TextSpan(text: text, style: style));
  }

  /// Removes lightweight markdown, returning plain text safe to share or copy:
  /// `**x**` and `` `x` `` keep their content, stray `*` are dropped, bullet
  /// markers keep their list shape.
  static String stripMarkdown(String text) {
    var out = text.trim();
    // Bold/code pairs keep their inner content.
    out = out.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    out = out.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!);
    // Remaining asterisks are decorative.
    out = out.replaceAll('*', '');
    return out;
  }
}
/// Detects and strips MedGemma's visible reasoning.
///
/// MedGemma-1.5-4B emits reasoning in one of two shapes:
///
/// 1. A self-critique loop:
///    ```
///    Draft 1: <first attempt>
///    Critique 1: <review>
///    Revise 1: <final answer>
///    ```
/// 2. A `thought` preamble:
///    ```
///    thought
///    <reasoning paragraph>
///
///    <final answer>
///    ```
///
/// Left unhandled these fill the context window, over-generate, and loop
/// (`Draft 2`, `Critique 2`, ...). This helper detects the markers, signals a
/// second round (used to cancel inference), and extracts the final answer.
class ReasoningTrace {
  ReasoningTrace._();

  /// A `Draft`/`Critique`/`Revise` heading at the start of a line, tolerating
  /// markdown bullets and bold markers, e.g. `**Critique 2:**`.
  static final RegExp _marker = RegExp(
    r'^[ \t>*#\-]*\b(draft|critique|revise)\b[ \t]*\d*[ \t]*[:.\-]\*{0,2}',
    caseSensitive: false,
    multiLine: true,
  );

  static final RegExp _draftMarker = RegExp(
    r'^[ \t>*#\-]*\bdraft\b[ \t]*\d*[ \t]*[:.\-]\*{0,2}',
    caseSensitive: false,
    multiLine: true,
  );

  /// A line that is just the `thought` channel heading.
  static final RegExp _thoughtLine = RegExp(
    r'^[ \t>*#\-]*thought[ \t]*[:*#]*[ \t]*$',
    caseSensitive: false,
    multiLine: true,
  );

  /// Filler MedGemma often emits inside `Revise` when it had no change.
  static final RegExp _filler = RegExp(
    r'^((no revision needed|no revisions needed|no changes? needed|seems good|looks good|no change)[^.\n]*[.:]?\s*)+',
    caseSensitive: false,
  );

  static final RegExp _blankLine = RegExp(r'\n[ \t]*\n');

  /// True when [text] contains reasoning (either format).
  static bool hasTrace(String text) =>
      _marker.hasMatch(text) || _thoughtLine.hasMatch(text);

  /// True once the model is looping (a second `Draft` or `thought` round).
  static bool isLooping(String text) =>
      _draftMarker.allMatches(text).length >= 2 ||
      _thoughtLine.allMatches(text).length >= 2;

  /// Returns the final answer from [text].
  ///
  /// Uses the content after the last `Revise` heading when present, otherwise
  /// strips a leading `thought` preamble. When there is no reasoning the
  /// trimmed input is returned unchanged.
  static String extractAnswer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final matches = _marker.allMatches(trimmed).toList();
    if (matches.isNotEmpty) {
      var chosen = matches.last;
      for (final m in matches.reversed) {
        if (m.group(1)!.toLowerCase() == 'revise') {
          chosen = m;
          break;
        }
      }

      var answer = trimmed.substring(chosen.end).trim();

      // If the chosen section immediately starts another round, skip it.
      final next = _marker.matchAsPrefix(answer);
      if (next != null) {
        answer = answer.substring(next.end).trim();
      }

      final cleaned = answer.replaceFirst(_filler, '').trim();
      return cleaned.isEmpty ? answer : cleaned;
    }

    final thought = _thoughtLine.firstMatch(trimmed);
    if (thought != null) {
      final body = trimmed.substring(thought.end);
      final sep = _blankLine.firstMatch(body);
      if (sep != null) {
        // Everything after the first blank line is the answer.
        return body.substring(sep.end).trim();
      }
      // No blank line yet: the reasoning has not finished.
      return '';
    }

    return trimmed;
  }
}

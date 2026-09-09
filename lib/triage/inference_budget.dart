import 'dart:math' as math;

import 'package:fllama/fllama.dart' show Message;

/// Per-call inference budgets for the local MedGemma worker (ADR-014).
///
/// fllama's OpenAI-style chat has no auto history management, and MedGemma's
/// visible reasoning consumes completion tokens before the real answer. To keep
/// replies from being truncated we compute `maxTokens` dynamically from the
/// measured prompt size every call:
///
/// - chat: total context fixed at [chatContextSize]; completion is whatever
///   remains after the measured prompt, clamped to a [chatCompletionFloor, cap]
///   band. When the prompt would push completion below the floor the history is
///   compacted ([compactHistory]) instead of overflowing the context window.
/// - summary: total context [summaryContextSize]; completion is dynamic too,
///   never dropping below [summaryCompletionFloor] so a strict-JSON reply
///   always has room.
///
/// Token estimate is a cheap heuristic (≈3.5 chars per token) used only to size
/// budgets; the native server still owns the real tokenization.
class InferenceBudget {
  InferenceBudget._();

  /// Rough chars-per-token heuristic for English text.
  static const double charsPerToken = 3.5;

  /// Completion budget for the Tier 2 summary call.
  static const int summaryContextSize = 4096;
  static const int summaryCompletionFloor = 1024;
  static const int summaryCompletionCap = 1536;
  static const int summaryHeadroom = 384;

  /// Completion budget for chat turns (prompt + reply fits in this window).
  static const int chatContextSize = 3072;
  static const int chatCompletionFloor = 512;
  static const int chatCompletionCap = 1536;
  static const int chatHeadroom = 192;

  /// Max prompt tokens (excluding completion) after which chat history must be
  /// compacted so that completion never drops below [chatCompletionFloor].
  static int get chatPromptCap =>
      chatContextSize - chatCompletionFloor - chatHeadroom;

  static int estimateTokens(String text) =>
      (text.length / charsPerToken).ceil();

  /// Dynamic `maxTokens` for the summary call given the prompt's token size.
  static int summaryCompletion(int promptTokens) => math.max(
        summaryCompletionFloor,
        math.min(
          summaryContextSize - promptTokens - summaryHeadroom,
          summaryCompletionCap,
        ),
      );

  /// Dynamic `maxTokens` for a chat turn given the prompt's token size.
  static int chatCompletion(int promptTokens) => math.max(
        chatCompletionFloor,
        math.min(chatContextSize - promptTokens - chatHeadroom,
            chatCompletionCap),
      );

  /// Keeps the newest [budgetTokens]-worth of [history], always retaining the
  /// last message (the pending user question). Callers pass only the chat
  /// transcript — system prompt and the attached triage context are sized
  /// separately and never dropped.
  static List<Message> compactHistory(
    List<Message> history,
    int budgetTokens,
  ) {
    if (history.isEmpty) return history;
    final keep = <Message>[];
    var running = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      running += estimateTokens(m.text);
      if (running > budgetTokens && keep.isNotEmpty) {
        break;
      }
      keep.insert(0, m);
    }
    if (keep.isEmpty) {
      keep.add(history.last);
    }
    return keep;
  }

  static int _tokensOf(List<Message> messages) =>
      messages.fold(0, (sum, m) => sum + estimateTokens(m.text));

  /// Convenience: prompt token count for a chat turn (system + optional
  /// attached triage context + transcript).
  static int chatPromptTokens({
    required String systemText,
    String? contextText,
    List<Message>? history,
  }) =>
      estimateTokens(systemText) +
      estimateTokens(contextText ?? '') +
      _tokensOf(history ?? const []);
}
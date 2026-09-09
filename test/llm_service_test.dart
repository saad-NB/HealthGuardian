import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/services/llm_service.dart';

void main() {
  group('LlmService.parseFinishedReason', () {
    test('extracts "stop" from a well-formed chunk', () {
      const json =
          '{"choices":[{"delta":{"content":"done"},"index":0,"finish_reason":"stop"}]}';
      expect(LlmService.parseFinishedReason(json), 'stop');
    });

    test('extracts "length" from a truncated response', () {
      const json =
          '{"choices":[{"delta":{"content":"cut"},"index":0,"finish_reason":"length"}]}';
      expect(LlmService.parseFinishedReason(json), 'length');
    });

    test('handles tool_calls and multiple choices', () {
      const json =
          '{"choices":[{"delta":{"content":""},"index":0,"finish_reason":null},'
          '{"delta":{"content":"tool"},"index":1,"finish_reason":"tool_calls"}]}';
      expect(LlmService.parseFinishedReason(json), 'tool_calls');
    });

    test('returns "unknown" on malformed or empty JSON', () {
      expect(LlmService.parseFinishedReason(''), 'unknown');
      expect(LlmService.parseFinishedReason('   '), 'unknown');
      expect(LlmService.parseFinishedReason('not json'), 'unknown');
      expect(LlmService.parseFinishedReason('{"a":1}'), 'unknown');
      expect(LlmService.parseFinishedReason(
        '{"choices":[]}',
      ), 'unknown');
      expect(LlmService.parseFinishedReason(
        '{"choices":[{"delta":{},"index":0}]}',
      ), 'unknown');
    });
  });
}
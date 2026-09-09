import 'package:fllama/fllama.dart' show Message, Role;
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/inference_budget.dart';

void main() {
  group('InferenceBudget.estimateTokens', () {
    test('estimates ~3.5 chars per token', () {
      expect(InferenceBudget.estimateTokens('hello'), 2);
      expect(InferenceBudget.estimateTokens(''), 0);
      expect(InferenceBudget.estimateTokens('a' * 100), 29);
    });
  });

  group('summaryCompletion (dynamic, ADR-014)', () {
    test('caps at 1536 when the prompt is tiny', () {
      expect(InferenceBudget.summaryCompletion(0), 1536);
      expect(
        InferenceBudget.summaryCompletion(100),
        1536,
      );
      expect(
        InferenceBudget.summaryCompletion(2500),
        InferenceBudget.summaryContextSize -
            2500 -
            InferenceBudget.summaryHeadroom,
      );
    });

    test('never drops below the 1024 floor', () {
      expect(InferenceBudget.summaryCompletion(4096), 1024);
      expect(InferenceBudget.summaryCompletion(30000), 1024);
    });

    test('stays between floor and cap', () {
      for (var p = 0; p <= 8192; p += 128) {
        final c = InferenceBudget.summaryCompletion(p);
        expect(c, greaterThanOrEqualTo(1024));
        expect(c, lessThanOrEqualTo(1536));
      }
    });
  });

  group('chatCompletion (fixed 3072 window)', () {
    test('caps at 1536 on a small prompt', () {
      expect(InferenceBudget.chatCompletion(0), 1536);
    });

    test('floors at 512 when the prompt is large', () {
      expect(InferenceBudget.chatCompletion(100000), 512);
    });

    test('prompt + completion always fit in 3072 after compaction target', () {
      final target = InferenceBudget.chatPromptCap;
      final completion = InferenceBudget.chatCompletion(target);
      expect(target + completion, lessThanOrEqualTo(
          InferenceBudget.chatContextSize - InferenceBudget.chatHeadroom));
    });
  });

  group('chatPromptCap', () {
    test('leaves the 512 completion floor plus headroom', () {
      expect(
        InferenceBudget.chatContextSize - InferenceBudget.chatPromptCap,
        InferenceBudget.chatCompletionFloor + InferenceBudget.chatHeadroom,
      );
    });
  });

  group('compactHistory', () {
    Message msg(String t) => Message(Role.user, t);

    test('keeps everything when within budget', () {
      final h = [msg('one'), msg('two'), msg('three')];
      expect(InferenceBudget.compactHistory(h, 100000), hasLength(3));
    });

    test('keeps the newest messages when over budget', () {
      final h = [
        msg('a' * 500),
        msg('b' * 500),
        msg('c' * 500),
        msg('d' * 500),
        msg('e' * 500),
      ];
      final kept = InferenceBudget.compactHistory(h, 300);
      expect(kept, isNotEmpty);
      expect(kept.last.text, 'e' * 500, reason: 'newest message always kept');
      expect(kept.fold<int>(0, (s, m) => s + m.text.length), lessThanOrEqualTo(300 * 4));
    });

    test('a single over-budget message is still returned', () {
      final h = [msg('x' * 10_000)];
      final kept = InferenceBudget.compactHistory(h, 10);
      expect(kept, hasLength(1));
      expect(kept.single.text, 'x' * 10_000);
    });

    test('empty history stays empty', () {
      expect(InferenceBudget.compactHistory(const [], 100), isEmpty);
    });
  });

  group('chatPromptTokens', () {
    test('sums system, context and history', () {
      final tokens = InferenceBudget.chatPromptTokens(
        systemText: 'a' * 35,
        contextText: 'b' * 35,
        history: [Message(Role.user, 'c' * 35)],
      );
      expect(tokens, 30);
    });
  });
}
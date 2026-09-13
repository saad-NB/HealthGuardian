import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/reasoning_trace.dart';

void main() {
  group('ReasoningTrace.hasTrace', () {
    test('detects a Draft/Critique/Revise trace', () {
      expect(ReasoningTrace.hasTrace('Draft 1: hello'), isTrue);
      expect(
        ReasoningTrace.hasTrace('Draft 1: a\nCritique 1: b\nRevise 1: c'),
        isTrue,
      );
    });

    test('tolerates markdown bold markers', () {
      expect(ReasoningTrace.hasTrace('**Critique 2:** nope'), isTrue);
    });

    test('detects a leading "thought" preamble', () {
      expect(
        ReasoningTrace.hasTrace(
          'thought\nThe user is asking for first aid. I need to answer.\n\n'
          '• Apply pressure.',
        ),
        isTrue,
      );
      expect(ReasoningTrace.hasTrace('thought\nstill reasoning'), isTrue);
    });

    test('is false for a plain answer', () {
      expect(ReasoningTrace.hasTrace('Drink water and rest.'), isFalse);
      expect(ReasoningTrace.hasTrace(''), isFalse);
    });
  });

  group('ReasoningTrace.isLooping', () {
    test('false with a single draft round', () {
      expect(
        ReasoningTrace.isLooping('Draft 1: a\nCritique 1: b\nRevise 1: c'),
        isFalse,
      );
    });

    test('true once a second draft round starts', () {
      expect(
        ReasoningTrace.isLooping(
          'Draft 1: a\nCritique 1: b\nRevise 1: c\nDraft 2: d',
        ),
        isTrue,
      );
    });

    test('true once a second thought round starts', () {
      expect(
        ReasoningTrace.isLooping('thought\na\n\nanswer\nthought\nb'),
        isTrue,
      );
    });
  });

  group('ReasoningTrace.extractAnswer', () {
    test('returns plain text unchanged', () {
      expect(
        ReasoningTrace.extractAnswer('  Drink water and rest.  '),
        'Drink water and rest.',
      );
    });

    test('extracts the last Revise section', () {
      const raw = 'Draft 1: first try\n'
          'Critique 1: needs work\n'
          'Revise 1: Give the patient fluids.';
      expect(ReasoningTrace.extractAnswer(raw), 'Give the patient fluids.');
    });

    test('drops the "no revision needed / seems good" filler', () {
      const raw = 'Draft 1: x\nCritique 1: y\n'
          'Revise 1: No revision needed. Seems good.Hello! I can help with that.';
      expect(
        ReasoningTrace.extractAnswer(raw),
        'Hello! I can help with that.',
      );
    });

    test('handles markdown-bold headings', () {
      const raw = '**Draft 1:** a\n**Revise 1:** Apply pressure to the wound.';
      expect(
        ReasoningTrace.extractAnswer(raw),
        'Apply pressure to the wound.',
      );
    });

    test('empty input stays empty', () {
      expect(ReasoningTrace.extractAnswer(''), '');
    });

    test('strips a "thought" preamble up to the first blank line', () {
      const raw = 'thought\n'
          'The user is asking for first aid for a wasp sting. I need to give '
          'concise, non-medication steps.\n'
          '\n'
          '• Identify the situation: Wasp sting on the arm.';
      expect(
        ReasoningTrace.extractAnswer(raw),
        '• Identify the situation: Wasp sting on the arm.',
      );
    });

    test('returns empty while a "thought" preamble has no answer yet', () {
      expect(ReasoningTrace.extractAnswer('thought\nstill reasoning'), '');
    });
  });
}

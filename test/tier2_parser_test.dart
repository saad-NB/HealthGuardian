import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2_parser.dart';

void main() {
  group('Tier2Parser.parse (fail-closed, ADR-014)', () {
    test('parses a clean strict-JSON reply', () {
      final a = Tier2Parser.parse(
        '{"triage_level":"P1","summary":"- a\\n- b\\n- c\\n- d","requires_human_verification":true}',
      );
      expect(a.suggestion, TriageTier.p1);
      expect(a.summary, contains('- a'));
      expect(a.requiresHumanVerification, isTrue);
    });

    test('tolerates prose wrapped around the JSON object', () {
      final raw =
          'Here is my analysis:\\n{"triage_level": "P2", '
          '"summary": "- high risk\\n- monitor"} \\nHope that helps.';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p2);
      expect(a.summary, contains('high risk'));
    });

    test('accepts lowercase and numeric tiers', () {
      expect(Tier2Parser.parse('{"triage_level":"p5","summary":"- x"}').suggestion,
          TriageTier.p5);
      expect(Tier2Parser.parse('{"triage_level":3,"summary":"- x"}').suggestion,
          TriageTier.p3);
      expect(Tier2Parser.parse('{"tier":"emergency","summary":"- x"}').suggestion,
          TriageTier.p1);
    });

    test('empty string fails closed to no suggestion', () {
      final a = Tier2Parser.parse('   ');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, isEmpty);
    });

    test('non-JSON garbage fails closed', () {
      final a = Tier2Parser.parse('I think the patient is fine.');
      expect(a.hasSuggestion, isFalse);
    });

    test('off-schema tier value fails closed (never guesses)', () {
      final a = Tier2Parser.parse('{"triage_level":"P9","summary":"- x"}');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, '- x');
    });

    test('missing tier key fails closed but keeps the summary', () {
      final a = Tier2Parser.parse('{"summary":"- nothing flagged"}');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, '- nothing flagged');
    });

    test('broken mid-string JSON fails closed but keeps raw', () {
      final raw =
          'thought\nThe vitals key was never closed: "triage_level": "';
      final a = Tier2Parser.parse(raw);
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, isEmpty);
      expect(a.rawOutput, raw);
    });

    test('nested strings with braces do not confuse the extractor', () {
      final raw = '{"triage_level":"P1","summary":"say } now"}';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p1);
      expect(a.summary, contains('} now'));
    });

    test('default requires_human_verification is true', () {
      final a = Tier2Parser.parse('{"triage_level":"P1","summary":"- x"}');
      expect(a.requiresHumanVerification, isTrue);
    });

    test('literal newlines inside the summary string still decode', () {
      final a = Tier2Parser.parse(
        '{"triage_level": "P5", "summary": "- Stable vitals.\n'
        '- Monitor closely.\n- Watch for worsening.", '
        '"requires_human_verification": true}',
      );
      expect(a.suggestion, TriageTier.p5);
      expect(a.summary, contains('Monitor closely'));
      expect(a.summary, isNot(contains(r'\n')));
    });

    test('MedGemma thought block before the JSON is skipped', () {
      final a = Tier2Parser.parse(
        'thought\n'
        'The patient is stable with no red flags.\n'
        '{"triage_level": "p5", "summary": "- Nothing serious."}',
      );
      expect(a.suggestion, TriageTier.p5);
      expect(a.summary, contains('Nothing serious'));
    });

    test('invalid JSON falls back to tolerant field extraction', () {
      final a = Tier2Parser.parse(
        'thought\nThe patient is fine.\n'
        '"triage_level": "P4",\n'
        '"summary": "- No danger signs.\n- Home care ok.",\n'
        '"requires_human_verification": true',
      );
      expect(a.suggestion, TriageTier.p4);
      expect(a.summary, contains('No danger signs'));
      expect(a.hasSuggestion, isTrue);
    });

    test('raw output is preserved even when extraction fails', () {
      final raw = 'thought\nNo JSON here at all.';
      final a = Tier2Parser.parse(raw);
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, isEmpty);
      expect(a.rawOutput, raw);
    });

    test('skips a leading reasoning object and reads the real summary object',
        () {
      final raw =
          '{"thought":"The patient looks P2 but let me be careful..."} '
          '{"triage_level":"P5","summary":"- stable\\n- minor","requires_human_verification":false}';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p5);
      expect(a.summary, contains('- stable'));
      expect(a.requiresHumanVerification, isFalse);
    });

    test('multi-brace scan keeps going when the first block is invalid', () {
      final raw =
          '{"thought":"triage"} {"broken": [ } {"triage_level":"P3","summary":"- follow up"}';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p3);
      expect(a.summary, contains('follow up'));
    });

    test('pure thought-only reply fails closed', () {
      final raw = '{"thought":"Not a real summary."} trailing words';
      final a = Tier2Parser.parse(raw);
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, isEmpty);
      expect(a.rawOutput, raw);
    });

    test('regex fallback ignores triage words inside a thought stanza', () {
      final raw =
          'Thought: I considered "triage_level": "P1" briefly, '
          'but really it is minor. "triage_level": "p5", "summary": "- ok"';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p5);
      expect(a.summary, '- ok');
    });
  });
}
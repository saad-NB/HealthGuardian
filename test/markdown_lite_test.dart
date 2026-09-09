import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/ui/text/markdown_lite.dart';

void main() {
  const base = TextStyle(fontSize: 15);

  group('MarkdownLite.buildSpans', () {
    test('plain text passes through as a single span', () {
      final spans = MarkdownLite.buildSpans('stable', style: base);
      expect(spans.length, 1);
      expect(spans.single.text, 'stable');
      expect(spans.single.style, base);
    });

    test('emits newlines between lines', () {
      final spans = MarkdownLite.buildSpans('a\nb', style: base);
      expect(spans.map((s) => s.text).toList(), ['a', '\n', 'b']);
    });

    test('dash bullets become bullet markers with trailing padding', () {
      final spans = MarkdownLite.buildSpans('- stable\n* minor', style: base);
      expect(spans.map((s) => s.text).toList(), [
        '•  ',
        'stable',
        '\n',
        '•  ',
        'minor',
      ]);
    });

    test('numbered bullets are converted to real bullets', () {
      final spans = MarkdownLite.buildSpans('1. first\n2) second', style: base);
      expect(spans.map((s) => s.text).toList(), [
        '•  ',
        'first',
        '\n',
        '•  ',
        'second',
      ]);
    });

    test('bold, italic and code runs get styled, the rest stays plain', () {
      final spans = MarkdownLite.buildSpans(
        '**BP** is 120/80 *roughly* `n/a`',
        style: base,
      );
      final texts = spans.map((s) => s.text).toList();
      expect(texts,
          ['BP', ' is 120/80 ', 'roughly', ' ', 'n/a']);
      expect(spans[0].style?.fontWeight, FontWeight.bold);
      expect(spans[2].style?.fontStyle, FontStyle.italic);
      expect(spans[4].style?.fontFamily, 'monospace');
    });

    test('nested-looking bold is not eaten as two italics', () {
      final spans =
          MarkdownLite.buildSpans('**urgent** case', style: base);
      expect(spans[0].text, 'urgent');
      expect(spans[0].style?.fontWeight, FontWeight.bold);
    });
  });

  group('MarkdownLite.stripMarkdown', () {
    test('removes bold/code delimiters but keeps content', () {
      expect(
        MarkdownLite.stripMarkdown('**BP** is `120/80` now.'),
        'BP is 120/80 now.',
      );
    });

    test('drops stray asterisks', () {
      expect(MarkdownLite.stripMarkdown('a*b*c'), 'abc');
    });

    test('leaves plain text untouched', () {
      expect(MarkdownLite.stripMarkdown('No markdown here.'), 'No markdown here.');
    });
  });
}
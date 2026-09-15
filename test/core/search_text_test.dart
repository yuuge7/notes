import 'package:flutter_test/flutter_test.dart';
import 'package:notes/core/util/search_text.dart';

void main() {
  group('terms', () {
    test('splits on anything that is not a letter or a digit', () {
      expect(SearchText.terms('  brake-pads, 2026!  '), [
        'brake',
        'pads',
        '2026',
      ]);
    });

    test('keeps accented letters and other scripts whole', () {
      expect(SearchText.terms('șosea Café 東京'), ['șosea', 'Café', '東京']);
    });

    test('stops at the term limit', () {
      expect(
        SearchText.terms(List.filled(20, 'word').join(' ')),
        hasLength(SearchText.maxTerms),
      );
    });
  });

  test('the match query quotes each term and matches it as a prefix', () {
    expect(SearchText.matchQuery(['OR', 'near']), '"OR"* "near"*');
  });

  group('fold', () {
    test('lower-cases and strips accents', () {
      expect(SearchText.fold('Șoseaua Café'), 'soseaua cafe');
    });

    test('keeps every offset where it was', () {
      const text = 'İstanbul Ünye';
      expect(SearchText.fold(text), hasLength(text.length));
    });
  });

  group('matches', () {
    test('marks the typed part of a word', () {
      expect(SearchText.matches('Rear brake pads', ['bra']), [(5, 8)]);
    });

    test('only at the start of a word', () {
      expect(SearchText.matches('zebra', ['bra']), isEmpty);
    });

    test('ignores case and accents', () {
      expect(SearchText.matches('Șosea Kiseleff', ['sose']), [(0, 4)]);
    });

    test('a word matching two terms is marked for the longer', () {
      expect(SearchText.matches('brake', ['b', 'bra']), [(0, 3)]);
    });

    test('nothing to mark without terms', () {
      expect(SearchText.matches('brake', []), isEmpty);
    });
  });

  group('snippet', () {
    test('leaves text alone when the match is near the top', () {
      const text = 'Rear brake pads are down to the metal.';
      final snippet = SearchText.snippet(
        text,
        SearchText.matches(text, ['metal']),
      );

      expect(snippet.text, text);
      expect(snippet.shift, 0);
    });

    test('starts a little before a match deep in a long line', () {
      final text = '${'word ' * 40}needle';
      final matches = SearchText.matches(text, ['needle']);
      final snippet = SearchText.snippet(text, matches);
      final (start, end) = matches.single;

      expect(snippet.text, startsWith('… word'));
      expect(
        snippet.text.substring(start + snippet.shift, end + snippet.shift),
        'needle',
      );
    });

    test('starts at the line of a match below the first few lines', () {
      const text = 'a\nb\nc\nd\ne\nf\nneedle in a haystack';
      final snippet = SearchText.snippet(
        text,
        SearchText.matches(text, ['needle']),
      );

      expect(snippet.text, '… needle in a haystack');
    });
  });
}

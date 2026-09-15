/// How typed search text becomes a full-text query, and where its words turn
/// up again in a note so they can be highlighted.
///
/// Words are split the way the index splits them — runs of letters and
/// digits — and compared without case or accents, so the highlight lands on
/// what the index matched.
abstract final class SearchText {
  /// Words honoured in one query. More narrows nothing in practice and only
  /// makes the query slower.
  static const maxTerms = 8;

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// The words in [raw], in order.
  static List<String> terms(String raw) => [
    for (final match in _word.allMatches(raw).take(maxTerms)) match[0]!,
  ];

  /// An FTS5 query for notes holding every term at the start of a word.
  ///
  /// Each term is quoted, so a word such as OR or NEAR is searched for rather
  /// than read as an operator. Terms hold only letters and digits, so they
  /// cannot contain a quote themselves.
  static String matchQuery(List<String> terms) =>
      terms.map((term) => '"$term"*').join(' ');

  /// [text] in lower case without accents, one code unit for one, so an
  /// offset into the result is the same offset into [text].
  static String fold(String text) {
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      final char = String.fromCharCode(unit);
      final lower = char.toLowerCase();
      // A few letters lower-case to two units (İ becomes i and a dot); those
      // keep their original so offsets stay aligned.
      final single = lower.length == 1 ? lower : char;
      buffer.write(_bare[single.codeUnitAt(0)] ?? single);
    }
    return buffer.toString();
  }

  /// Where [terms] begin words in [text], as start and end offsets in reading
  /// order. A word matching several terms is marked for the longest.
  static List<(int, int)> matches(String text, List<String> terms) {
    if (terms.isEmpty || text.isEmpty) return const [];
    final wanted = [for (final term in terms) fold(term)]
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final word in _word.allMatches(fold(text)))
        for (final term in wanted.take(1).followedBy(wanted.skip(1)))
          if (word[0]!.startsWith(term)) (word.start, word.start + term.length),
    ]._firstPerStart();
  }

  /// [text] from near its first match, for a card that shows only the first
  /// lines of a note. A match inside those lines leaves the text whole.
  ///
  /// Returns the text to show and the amount to add to an offset in [text]
  /// to find the same place in it.
  static ({String text, int shift}) snippet(
    String text,
    List<(int, int)> matches, {
    int visibleChars = 140,
    int visibleLines = 5,
    int lead = 48,
  }) {
    if (matches.isEmpty) return (text: text, shift: 0);
    final first = matches.first.$1;
    final linesBefore = '\n'.allMatches(text.substring(0, first)).length;
    if (first < visibleChars && linesBefore < visibleLines) {
      return (text: text, shift: 0);
    }

    // Start at the beginning of the match's own line when that is close, or
    // on a word boundary a little before the match when the line is long.
    var start = text.lastIndexOf('\n', first) + 1;
    if (first - start > lead) {
      start = first - lead;
      final space = text.indexOf(' ', start);
      if (space >= 0 && space < first) start = space + 1;
    }
    const ellipsis = '… ';
    return (
      text: '$ellipsis${text.substring(start)}',
      shift: ellipsis.length - start,
    );
  }

  // Only letters Unicode decomposes into a base letter and a mark, as the
  // index's remove_diacritics does: ł or ø stay themselves there, so they
  // stay themselves here.
  static final Map<int, String> _bare = {
    for (final (letters, base) in const [
      ('àáâãäåāăą', 'a'),
      ('çćĉċč', 'c'),
      ('ď', 'd'),
      ('èéêëēĕėęě', 'e'),
      ('ĝğġģ', 'g'),
      ('ĥ', 'h'),
      ('ìíîïĩīĭį', 'i'),
      ('ĵ', 'j'),
      ('ķ', 'k'),
      ('ĺļľ', 'l'),
      ('ñńņň', 'n'),
      ('òóôõöōŏő', 'o'),
      ('ŕŗř', 'r'),
      ('śŝşšș', 's'),
      ('ţťț', 't'),
      ('ùúûüũūŭůűų', 'u'),
      ('ŵ', 'w'),
      ('ýÿŷ', 'y'),
      ('źżž', 'z'),
    ])
      for (final unit in letters.codeUnits) unit: base,
  };
}

extension on List<(int, int)> {
  /// Keeps the first range for each start. Terms are tried longest first, so
  /// that is the longest match for the word.
  List<(int, int)> _firstPerStart() {
    final seen = <int>{};
    return [
      for (final range in this)
        if (seen.add(range.$1)) range,
    ];
  }
}

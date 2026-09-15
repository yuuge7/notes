import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/util/search_text.dart';

/// Text with the words a search matched washed in the accent colour, the way
/// a highlighter goes over a printed page.
class MarkedText extends StatelessWidget {
  const MarkedText(
    this.text, {
    required this.style,
    this.terms = const [],
    this.ranges,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;
  final TextStyle style;

  /// Search words to mark wherever they begin a word.
  final List<String> terms;

  /// Exact start and end offsets to mark, used instead of [terms].
  final List<(int, int)>? ranges;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final marks = ranges ?? SearchText.matches(text, terms);
    if (marks.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final mark = TextStyle(backgroundColor: Theme.of(context).colors.mark);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in marks) {
      if (start < at || end > text.length) continue;
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: mark));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

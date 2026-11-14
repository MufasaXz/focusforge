/// Conservative boundaries for a message containing several requests.
/// Topic conjunctions ("acids and bases"), durations and decimals stay intact.
abstract final class CompoundMessage {
  static const maxParts = 4;

  static final _boundaries = RegExp(
    r'[?？\r\n]+|(?:^|\s)\d+[.)]\s+|(?:^|\s)[•●]\s*|'
    r'(?:^|\n)\s*[-*]\s+|\b(?:and\s+also|also|then|aur)\b',
    caseSensitive: false,
  );
  static final _and = RegExp(r'\band\b', caseSensitive: false);
  static final _question = RegExp(
    r'^(?:(?:please|pls)\s+)?(?:what|whats|how|why|when|where|which|who|'
    r'is|are|do|does|can|could|would|explain|define|tell|teach|quiz|compare)\b',
    caseSensitive: false,
  );
  static final _hinglishQuestion = RegExp(
    r'\b(?:kya|kaise|kitna|kitne|kab)\b.+\b(?:hai|hain|kare|karu)\b',
    caseSensitive: false,
  );
  static final _request = RegExp(
    r'^(?:explain|define|teach|compare)\s+\S+',
    caseSensitive: false,
  );

  static String _clean(String text) => text
      .replaceAll(RegExp(r'^\s*[-*]\s+'), '')
      .replaceAll(RegExp(r'^[\s.,;:!]+|[\s.,;:!]+$'), '')
      .trim();

  static bool _completeQuestion(String text) {
    final clean = _clean(text);
    return _request.hasMatch(clean) ||
        clean.split(RegExp(r'\s+')).length >= 3 &&
            (_question.hasMatch(clean) || _hinglishQuestion.hasMatch(clean));
  }

  static List<String> split(String input) {
    final parts = <String>[];
    for (final chunk in input.split(_boundaries)) {
      var start = 0;
      for (final match in _and.allMatches(chunk)) {
        final left = chunk.substring(start, match.start);
        final right = chunk.substring(match.end);
        if (_completeQuestion(left) && _completeQuestion(right)) {
          parts.add(_clean(left));
          start = match.end;
        }
      }
      final rest = _clean(chunk.substring(start));
      if (rest.isNotEmpty) parts.add(rest);
    }
    // Even empty, punctuation-only or separator-only input deserves a reply.
    return parts.isEmpty ? [input.trim()] : parts;
  }
}

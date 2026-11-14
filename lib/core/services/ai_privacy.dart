/// Data minimization at the device boundary. Pattern redaction is a defence in
/// depth, not anonymization: arbitrary names and personal details in free text
/// cannot reliably be recognized. Keep this aligned with the Worker's parser.
abstract final class AiPrivacy {
  static const studyFields = {
    'daysToExam',
    'todayMinutes',
    'goalMinutes',
    'weekMinutes',
    'lastWeekSameDaysMinutes',
    'streak',
  };

  static Map<String, dynamic> studyContext(Map<String, dynamic>? raw) => {
    for (final key in studyFields)
      if (raw?[key] case final int value when value >= 0)
        key: value.clamp(0, 100000),
  };

  static String text(
    String value, {
    int maxChars = 500,
    Iterable<String> privateValues = const [],
  }) {
    // Bound work before running expressions, but redact before the final cap so
    // an email or identifier spanning the display limit is not partly leaked.
    var clean = value.length > 16384 ? value.substring(0, 16384) : value;
    clean = clean.replaceAll(
      RegExp(
        r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060\ufeff]',
      ),
      '',
    );
    for (final pattern in [
      r'(?:https?://|www\.)[^\s<>]+',
      r'[a-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+',
      r'\b(?:[a-z][a-z0-9_]*\.){2,}[a-z][a-z0-9_]*\b',
      r'\b(?:\d{1,3}\.){3}\d{1,3}\b',
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
      r'\b[0-9a-f]{16,}\b',
      r'\b(?:imei|imsi|ssaid|android[_ -]?id|aaid|idfa|device[_ -]?id)\s*[:=]?\s*[a-z0-9_-]{6,}\b',
    ]) {
      clean = clean.replaceAll(
        RegExp(pattern, caseSensitive: false),
        '[redacted]',
      );
    }
    clean = clean.replaceAllMapped(RegExp(r'\+?\d[\d\s().-]{6,}\d'), (m) {
      return RegExp(r'\d').allMatches(m[0]!).length >= 8 ? '[redacted]' : m[0]!;
    });
    final values = <String>{
      for (final value in privateValues)
        if (value.trim().isNotEmpty) value.trim(),
      for (final value in privateValues)
        for (final part in value.trim().split(RegExp(r'\s+')))
          if (part.length >= 3) part,
    }.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final value in values) {
      clean = clean.replaceAll(
        RegExp(
          '(?<![\\p{L}\\p{N}_])${RegExp.escape(value)}(?![\\p{L}\\p{N}_])',
          caseSensitive: false,
          unicode: true,
        ),
        '[redacted]',
      );
    }
    clean = clean
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return clean.length > maxChars ? clean.substring(0, maxChars) : clean;
  }

  /// Expire the bounded local review cache on startup and whenever a report is
  /// added. No background processing runs while the app is not in use.
  static Map<String, dynamic> reports(
    Map<String, dynamic>? raw, {
    required DateTime now,
    Iterable<String> privateValues = const [],
  }) {
    final items = raw?['items'];
    final recent = <Map<String, dynamic>>[];
    if (items is List) {
      for (final item in items.whereType<Map>()) {
        final at = DateTime.tryParse(
          item['at'] is String ? item['at'] as String : '',
        );
        if (at == null ||
            at.isBefore(now.subtract(const Duration(days: 90))) ||
            at.isAfter(now)) {
          continue;
        }
        if (!const ['harmful', 'hate', 'incorrect'].contains(item['reason'])) {
          continue;
        }
        recent.add({
          'at': at.toIso8601String(),
          'reason': item['reason'],
          'reply': text(
            item['reply'] is String ? item['reply'] as String : '',
            maxChars: 900,
            privateValues: privateValues,
          ),
          if (item['question'] is String)
            'question': text(
              item['question'] as String,
              maxChars: 300,
              privateValues: privateValues,
            ),
        });
      }
    }
    return {
      if (raw?['ownerUid'] is String) 'ownerUid': raw!['ownerUid'],
      'items': recent
          .skip(recent.length > 50 ? recent.length - 50 : 0)
          .toList(),
    };
  }
}

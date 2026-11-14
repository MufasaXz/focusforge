/// Small, bounded text helpers shared by the on-device tutor. They do not
/// inspect accounts, installed apps, or any service outside the conversation.
abstract final class OfflineText {
  static const maxInputLength = 2000;

  static String normalize(String text) {
    var value = text.toLowerCase();
    const digits = '०१२३४५६७८९';
    for (var i = 0; i < digits.length; i++) {
      value = value.replaceAll(digits[i], '$i');
    }
    return value
        .replaceAll(RegExp('[’‘`\u0027]'), '')
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Whole phrases only: "art" must not match "start", for example.
  static bool has(String text, String phrase) =>
      ' $text '.contains(' ${normalize(phrase)} ');

  static bool any(String text, Iterable<String> phrases) =>
      phrases.any((phrase) => has(text, phrase));

  /// One edit, including an adjacent transposition. Applied only to bounded
  /// topic words, never to arbitrary whole prompts or command names.
  static bool close(String a, String b) {
    if (a == b) return true;
    if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
      return false;
    }
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length == b.length) {
        if (i + 1 < a.length && a[i] == b[j + 1] && a[i + 1] == b[j]) {
          i += 2;
          j += 2;
        } else {
          i++;
          j++;
        }
      } else if (a.length > b.length) {
        i++;
      } else {
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}

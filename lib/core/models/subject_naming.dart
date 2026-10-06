import 'study.dart';

/// How a subject's name becomes its id, and why a name cannot be used.
///
/// The id is the store's key and the name is the picker's identity, so the two
/// have to be derived the same way everywhere a subject can be created. There
/// is more than one such place — the onboarding picker and the focus tab both
/// add subjects — and a rule that lived in one of them would let the other
/// create a subject that `remove` or `setWeeklyTarget` then hits twice.
class SubjectNaming {
  const SubjectNaming._();

  /// The store's key for a subject name.
  ///
  /// Lowercased and reduced to `[a-z0-9-]` so the id is stable across launches
  /// and safe to log. A name with no ASCII alphanumerics at all — "!!!", "📚",
  /// "数学" — reduces to nothing, and an empty id is not merely ugly: every
  /// such subject would share one key, so the second is rejected as a
  /// duplicate of the first and `remove`/`setWeeklyTarget` would hit all of
  /// them at once. The fallback encodes the code units instead, which is
  /// deterministic across launches in a way `String.hashCode` does not
  /// promise.
  static String slug(String name) {
    final trimmed = name.trim();
    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isNotEmpty) return slug;
    // Radix-36 digits never contain '-', so the separator is unambiguous.
    return 's-${trimmed.codeUnits.map((u) => u.toRadixString(36)).join('-')}';
  }

  /// Why [rawName] cannot be used for a new subject, or null when it can.
  ///
  /// [existing] is what the store already holds; [reserved] is names that are
  /// on offer but not yet stored — the onboarding picker's unselected
  /// templates, which the user must not be able to duplicate by hand.
  ///
  /// Names are the picker's identity and slug ids are the store's, so either
  /// can collide. Two different names can slug to one id — "Math!" against
  /// "Math" — and then `setWeeklyTarget` and `remove` would hit both subjects
  /// at once. The caller renders this next to the field rather than failing
  /// silently.
  static String? reasonUnavailable(
    String rawName, {
    required Iterable<Subject> existing,
    Iterable<String> reserved = const [],
  }) {
    final name = rawName.trim();
    if (name.isEmpty) return 'Give it a name.';
    final normalised = name.toLowerCase();

    for (final subject in existing) {
      if (subject.name.trim().toLowerCase() == normalised) {
        return '“${subject.name}” is already on your list.';
      }
    }
    for (final taken in reserved) {
      if (taken.trim().toLowerCase() == normalised) {
        return '“$taken” is already on your list.';
      }
    }

    final id = slug(name);
    for (final subject in existing) {
      if (subject.id == id) {
        return 'That name is too similar to “${subject.name}”.';
      }
    }
    for (final taken in reserved) {
      if (slug(taken) == id) return 'That name is too similar to “$taken”.';
    }
    return null;
  }
}

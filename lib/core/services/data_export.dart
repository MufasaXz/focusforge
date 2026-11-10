import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_store.dart';

import 'export/download_stub.dart'
    if (dart.library.js_interop) 'export/download_web.dart';

/// What became of a request to save the export as a file.
enum ExportOutcome { saved, cancelled, failed, unsupported }

/// Saves "Export all data" as a JSON file: the system file picker on
/// Android, a download in the browser. Other platforms keep the copy action.
class DataExport {
  const DataExport._();

  static const _channel = MethodChannel('dev.focusforge/export');

  /// Whether this platform can save a file at all.
  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// A dated name, so a second export does not land on the first.
  static String fileName(DateTime day) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'focusforge-export-${day.year}-${two(day.month)}-${two(day.day)}.json';
  }

  /// Keys kept once per account, ending in that account's id.
  static const _accountKeyPrefixes = [
    'study.account.',
    'study.modified.',
    'assistant.account.',
    'leaderboard.consent.',
    'achievements.linked.',
  ];

  /// Keys holding one JSON map with an entry per account id.
  static const _accountMapKeys = {
    StoreKeys.achievementAccounts,
    StoreKeys.achievementLinkedOwners,
    StoreKeys.achievementAliases,
  };

  /// The part of [all] that belongs to the account [uid].
  ///
  /// The store also keeps a snapshot for every other account that has used
  /// this phone, so each gets its own study and its own chat with Pip back
  /// when it signs in again. Those are someone else's name, photo, history
  /// and messages: whoever holds the phone now must not be handed them in a
  /// file. A guest id that was later linked to [uid] counts as [uid].
  static Map<String, Object?> forAccount(Map<String, Object?> all, String uid) {
    final aliases = _decode(all[StoreKeys.achievementAliases]);
    final own = <String>{
      uid,
      for (final entry in aliases.entries)
        if (entry.value == uid) entry.key,
    };
    final out = <String, Object?>{};
    for (final entry in all.entries) {
      final key = entry.key;
      // The id of an account deleted from this phone, kept only so its
      // signed-in session cannot come back. It is nobody's data to export.
      if (key == 'auth.deletedCredential') continue;
      final prefix = _accountKeyPrefixes
          .where((prefix) => key.startsWith(prefix))
          .firstOrNull;
      if (prefix != null) {
        if (own.contains(key.substring(prefix.length))) out[key] = entry.value;
        continue;
      }
      if (_accountMapKeys.contains(key)) {
        final mine = {
          for (final row in _decode(entry.value).entries)
            if (own.contains(row.key)) row.key: row.value,
        };
        if (mine.isNotEmpty) out[key] = jsonEncode(mine);
        continue;
      }
      out[key] = entry.value;
    }
    return out;
  }

  static Map<String, dynamic> _decode(Object? raw) {
    if (raw is! String) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  static Future<ExportOutcome> save(String name, String json) async {
    if (kIsWeb) {
      return download(name, json) ? ExportOutcome.saved : ExportOutcome.failed;
    }
    if (!supported) return ExportOutcome.unsupported;
    try {
      final result = await _channel.invokeMethod<String>('save', {
        'name': name,
        'json': json,
      });
      return switch (result) {
        'saved' => ExportOutcome.saved,
        'cancelled' => ExportOutcome.cancelled,
        'unsupported' => ExportOutcome.unsupported,
        _ => ExportOutcome.failed,
      };
    } on PlatformException {
      return ExportOutcome.failed;
    } on MissingPluginException {
      return ExportOutcome.unsupported;
    }
  }
}

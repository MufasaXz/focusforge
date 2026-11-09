import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

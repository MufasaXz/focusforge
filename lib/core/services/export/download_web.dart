import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Starts a browser download of [json] named [name]. False when the browser
/// refuses it.
bool download(String name, String json) {
  try {
    final blob = web.Blob(
      [json.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    link.click();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}

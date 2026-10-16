import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A small re-encoded thumbnail; original files and image metadata stay private.
class ProfilePhoto {
  static const maxLength = 24000;

  static String encode(Uint8List source) {
    if (source.length > 12 * 1024 * 1024) {
      throw const FormatException('Image too large');
    }
    final decoded = img.decodeImage(source);
    if (decoded == null) throw const FormatException('Image unavailable');
    final oriented = img.bakeOrientation(decoded);
    final thumbnail = img.copyResizeCropSquare(oriented, size: 128);
    // Copy pixels to a new image so EXIF, GPS and other metadata are discarded.
    final clean = img.Image(width: 128, height: 128, numChannels: 3);
    img.compositeImage(clean, thumbnail);
    for (final quality in [80, 65, 45]) {
      final encoded = base64Encode(img.encodeJpg(clean, quality: quality));
      if (encoded.length <= maxLength) return encoded;
    }
    throw const FormatException('Image too large');
  }

  static Uint8List? bytes(String? value) {
    if (value == null || value.isEmpty || value.length > maxLength) return null;
    try {
      final bytes = base64Decode(value);
      if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) return null;
      final info = img.JpegDecoder().startDecode(bytes);
      if (info == null ||
          info.width > 256 ||
          info.height > 256 ||
          info.width < 1 ||
          info.height < 1) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String? valid(Object? value) =>
      value is String && bytes(value) != null ? value : null;
}

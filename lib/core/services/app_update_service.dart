import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'local_store.dart';

/// Only public release metadata is requested: no account/device identifiers,
/// credentials, study totals or analytics are attached to the request.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.page,
    required this.notes,
  });

  final String version;
  final int buildNumber;
  final Uri page;
  final String notes;
  String get id => '$version+$buildNumber';

  static const repository = 'MufasaXz/focusforge';
  static final _version = RegExp(
    r'^(?:v)?(\d{1,5})\.(\d{1,5})\.(\d{1,5})(?:\+(\d{1,10}))?$',
  );

  static int? compareVersions(String a, String b) {
    final x = _version.firstMatch(a);
    final y = _version.firstMatch(b);
    if (x == null || y == null) return null;
    for (var i = 1; i <= 3; i++) {
      final difference = int.parse(x[i]!).compareTo(int.parse(y[i]!));
      if (difference != 0) return difference;
    }
    return 0;
  }

  static AppRelease? parse(
    Object? json, {
    String currentVersion = kAppVersion,
    int currentBuild = kAppBuildNumber,
  }) {
    if (json is! Map<String, dynamic> ||
        json['draft'] != false ||
        json['prerelease'] != false) {
      return null;
    }
    final tag = json['tag_name'];
    if (tag is! String || tag.length > 40) return null;
    final version = _version.firstMatch(tag);
    final order = compareVersions(tag, currentVersion);
    if (version == null || order == null || order < 0) return null;
    final label = '${version[1]}.${version[2]}.${version[3]}';
    // Construct and validate the destination instead of opening arbitrary
    // URLs from remote metadata. No HTML/Markdown links are executed in-app.
    final page = Uri.https('github.com', '/$repository/releases/tag/$tag');
    if (json['html_url'] != page.toString()) return null;
    final assets = json['assets'];
    if (assets is! List) return null;
    final body = json['body'];
    final metadata = body is String
        ? RegExp(r'<!--\s*focusforge-build:\s*(\d{1,10})\s*-->')
              .allMatches(body)
              .toList()
        : <RegExpMatch>[];
    final releaseBuild = metadata.length == 1
        ? int.tryParse(metadata.single[1]!)
        : null;
    var newestBuild = 0;
    final filename = RegExp(
      '^focusforge-${RegExp.escape(label)}-([0-9]{1,10})\\.apk\$',
    );
    for (final asset in assets) {
      if (asset is! Map || asset['state'] != 'uploaded') continue;
      final name = asset['name'];
      if (name is! String) continue;
      final match = filename.firstMatch(name);
      final build = name == 'FocusForge-$label.apk'
          ? releaseBuild
          : match == null
          ? null
          : int.tryParse(match[1]!);
      if (build == null || build > 2100000000 || build <= currentBuild) {
        continue;
      }
      if (version[4] != null && int.parse(version[4]!) != build) continue;
      final url = Uri.https(
        'github.com',
        '/$repository/releases/download/$tag/$name',
      );
      if (asset['browser_download_url'] != url.toString()) continue;
      if (asset['size'] is! int || (asset['size'] as int) <= 0) continue;
      if (build > newestBuild) newestBuild = build;
    }
    if (newestBuild == 0) return null;
    final notes = body is String
        ? body
              .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
              .replaceAllMapped(
                RegExp(r'\[([^\]]+)\]\([^)]*\)'),
                (match) => match[1]!,
              )
              .replaceAll(RegExp(r'[#*`\x00-\x08\x0b-\x1f\x7f]'), '')
              .trim()
        : '';
    return AppRelease(
      version: label,
      buildNumber: newestBuild,
      page: page,
      notes: notes.length > 1600 ? '${notes.substring(0, 1600)}…' : notes,
    );
  }
}

class AppUpdateService {
  AppUpdateService(
    this.store, {
    this.enabled = true,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  final LocalStore store;
  final bool enabled;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;
  static const lastCheckKey = 'updates.lastCheck';
  static const shownReleaseKey = 'updates.shownRelease';
  static const maxBytes = 256 * 1024;
  AppRelease? _cached;
  Future<AppRelease?>? _inFlight;

  bool wasShown(AppRelease release) =>
      store.getString(shownReleaseKey) == release.id;
  Future<void> markShown(AppRelease release) =>
      store.setString(shownReleaseKey, release.id);

  Future<AppRelease?> check({bool force = false}) {
    if (!enabled) return Future.value(null);
    return _inFlight ??= _check(force).whenComplete(() => _inFlight = null);
  }

  Future<AppRelease?> _check(bool force) async {
    final now = _now().millisecondsSinceEpoch;
    final last = store.getInt(lastCheckKey);
    if (!force &&
        last != null &&
        now >= last &&
        now - last < const Duration(hours: 24).inMilliseconds) {
      return _cached;
    }
    await store.setInt(lastCheckKey, now);
    final client = _clientFactory();
    try {
      return _cached = await _fetch(client).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline, rate-limited, malformed or unavailable: leave the app usable.
      return null;
    } finally {
      client.close();
    }
  }

  Future<AppRelease?> _fetch(http.Client client) async {
    final response = await client.send(
      http.Request(
          'GET',
          Uri.https(
            'api.github.com',
            '/repos/${AppRelease.repository}/releases/latest',
          ),
        )
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'FocusForge-update-check',
          'X-GitHub-Api-Version': '2022-11-28',
        }),
    );
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxBytes) {
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) return null;
      bytes.addAll(chunk);
    }
    return AppRelease.parse(jsonDecode(utf8.decode(bytes)));
  }
}

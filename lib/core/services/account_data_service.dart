import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_backend_service.dart' show AiBackendService, IdTokenSource;
import 'app_attestation.dart';

abstract interface class AccountData {
  Future<Map<String, dynamic>> export();
  Future<void> erase();
}

/// Account control is independent of Pip consent: no model is called here.
/// A failed page aborts export/deletion instead of reporting partial success.
class AccountDataService implements AccountData {
  AccountDataService({
    required this.idToken,
    http.Client? client,
    IdTokenSource? appCheckToken,
    Uri? accountEndpoint,
    Uri? legacyEndpoint,
  }) : _client = client ?? http.Client(),
       _appCheckToken = appCheckToken ?? appAttestationToken,
       _account =
           accountEndpoint ??
           Uri.parse('https://www.focus-forge.in/api/account-data'),
       _legacy =
           legacyEndpoint ??
           Uri.parse(AiBackendService.defaultEndpoint).resolve('/data');

  final IdTokenSource idToken;
  final IdTokenSource _appCheckToken;
  final http.Client _client;
  final Uri _account;
  final Uri _legacy;
  static const sections = [
    'account',
    'profile',
    'achievements',
    'stats',
    'appStats',
    'preferences',
    'sessions',
    'sessionData',
    'guardian',
    'children',
    'remoteRules',
    'progress',
    'catalog',
    'deletionRefs',
    'entries',
    'members',
    'pipReports',
    'limits',
    'pairCodesChild',
    'pairCodesGuardian',
  ];

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw StateError('Account service unavailable');
    }
    final token = await idToken();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to manage cloud data');
    }
    final attestation = await _appCheckToken();
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-firebase-appcheck': ?attestation,
      })
      ..body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
        'Cloud data request could not finish. Sign in again and retry.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Account service unavailable');
    }
    return decoded;
  }

  Future<List<dynamic>> _pages(Uri endpoint, Map<String, dynamic> body) async {
    final records = <dynamic>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await _post(endpoint, {...body, 'cursor': ?cursor});
      if (!page.containsKey('cursor') ||
          page['records'] is! List ||
          (page['cursor'] != null && page['cursor'] is! String)) {
        throw StateError('Cloud data response incomplete');
      }
      records.addAll(page['records'] as List);
      cursor = page['cursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw StateError('Cloud data response incomplete');
      }
    } while (cursor != null);
    return records;
  }

  @override
  Future<Map<String, dynamic>> export() async => {
    'firebase': [
      for (final section in sections)
        ...await _pages(_account, {'operation': 'export', 'section': section}),
    ],
    'legacyPipReports': await _pages(_legacy, {'operation': 'export'}),
  };

  void close() => _client.close();

  @override
  Future<void> erase() async {
    // This establishes an immutable server fence before report erasure.
    await _erasePages();
    await _pages(_legacy, {'operation': 'delete'});
    // The final request also removes the temporary account-control counter.
    await _erasePages();
  }

  Future<void> _erasePages() async {
    for (;;) {
      final page = await _post(_account, {'operation': 'erase'});
      if (page['done'] is! bool) {
        throw StateError('Cloud cleanup response incomplete');
      }
      if (page['done'] == true) return;
    }
  }
}

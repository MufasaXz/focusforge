import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:focusforge/core/services/account_data_service.dart';

void main() {
  AccountDataService service(MockClientHandler handler) => AccountDataService(
    idToken: () async => 'fixture-token',
    appCheckToken: () async => null,
    client: MockClient(handler),
  );
  test(
    'export includes every server section and all legacy report pages',
    () async {
      final sections = <String>{};
      final data = await service((request) async {
        expect(request.url.scheme, 'https');
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], 'Bearer fixture-token');
        final body = jsonDecode(request.body) as Map;
        if (body['section'] case final String section) {
          sections.add(section);
          return http.Response(
            jsonEncode({
              'records': [
                {'path': section},
              ],
              'cursor': null,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'records': [
              {'key': body['cursor'] ?? 'first'},
            ],
            'cursor': body['cursor'] == null ? 'next' : null,
          }),
          200,
        );
      }).export();
      expect(sections, AccountDataService.sections.toSet());
      expect(data['legacyPipReports'], hasLength(2));
    },
  );
  test('erasure fences reports first, drains pages, then finishes auxiliary cleanup', () async {
    final calls = <String>[];
    var erasures = 0;
    await service((request) async {
      final body = jsonDecode(request.body) as Map;
      calls.add(body['operation'] as String);
      return http.Response(
        jsonEncode(
          body['operation'] == 'erase'
              ? {'done': ++erasures > 1}
              : {
                  'records': [],
                  'cursor': body['cursor'] == null ? 'second' : null,
                },
        ),
        200,
      );
    }).erase();
    expect(calls, ['erase', 'erase', 'delete', 'delete', 'erase']);
  });
  test('a failed page prevents false export or deletion completion', () async {
    final api = service(
      (_) async => http.Response('{"error":"unavailable"}', 503),
    );
    await expectLater(api.export(), throwsStateError);
    await expectLater(api.erase(), throwsStateError);
  });
}

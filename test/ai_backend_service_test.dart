// Pip's online client.
//
// WHAT INVARIANT: a question goes to the worker only with the signed-in
// user's ID token, trimmed to 300 characters; a good reply comes back as
// text; every failure (signed out, offline, slow, rate limited, blocked,
// down) arrives as one AiFailure the chat can explain.
//
// WHY IT MATTERS: the chat falls back to the phone on exactly these
// failures. A misread status would leave the user with no answer at all.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:focusforge/core/services/ai_backend_service.dart';

void main() {
  final endpoint = Uri.parse('https://pip.example.workers.dev/');

  AiBackendService service(
    MockClientHandler handler, {
    String? token = 'id-token',
    Duration timeout = const Duration(seconds: 25),
  }) => AiBackendService(
    endpoint: endpoint,
    idToken: () async => token,
    client: MockClient(handler),
    timeout: timeout,
  );

  Future<AiFailure> failureOf(Future<String> call) async {
    try {
      await call;
    } on AiBackendException catch (error) {
      return error.failure;
    }
    fail('Expected an AiBackendException');
  }

  test('consent withdrawn while the token loads sends nothing', () async {
    var requests = 0;
    var consent = true;
    final token = Completer<String?>();
    final backend = AiBackendService(
      client: MockClient((request) async {
        requests++;
        return http.Response(jsonEncode({'reply': 'x'}), 200);
      }),
      idToken: () => token.future,
      endpoint: endpoint,
    );
    final asking = failureOf(
      backend.askAiAssistant(
        userMessage: 'plan my week',
        allowed: () => consent,
      ),
    );
    consent = false;
    token.complete('id-token');
    expect(await asking, AiFailure.withdrawn);
    expect(requests, 0);
  });

  test('a question carries the token and comes back as text', () async {
    late http.Request sent;
    final reply =
        await service((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'reply': '  Start with Physics.  ',
              'provider': 'gemini',
            }),
            200,
          );
        }).askAiAssistant(
          userMessage: '  ${'z' * 400}  ',
          extraContext: {'exam': 'NEET-UG'},
          history: const [
            {'role': 'pip', 'text': 'Hi!'},
          ],
          locale: 'hi',
        );

    expect(reply, 'Start with Physics.');
    expect(sent.method, 'POST');
    expect(sent.url, endpoint);
    expect(sent.headers['authorization'], 'Bearer id-token');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect((body['message'] as String).length, 300);
    expect(body['context'], isEmpty);
    expect(body['locale'], 'hi');
    expect(body['history'], hasLength(1));
  });

  test('without a sign-in nothing is sent', () async {
    var calls = 0;
    final backend = service((request) async {
      calls++;
      return http.Response('{}', 200);
    }, token: null);
    expect(
      await failureOf(backend.askAiAssistant(userMessage: 'hi')),
      AiFailure.signedOut,
    );
    expect(calls, 0);
    expect(
      await failureOf(
        AiBackendService(
          endpoint: endpoint,
          idToken: () => throw StateError('Firebase is not set up'),
          client: MockClient((_) async => http.Response('{}', 200)),
        ).askAiAssistant(userMessage: 'hi'),
      ),
      AiFailure.signedOut,
    );
    expect(
      await failureOf(backend.askAiAssistant(userMessage: '   ')),
      AiFailure.invalid,
    );
  });

  test('each worker status maps to one failure', () async {
    final cases = <(int, Map<String, Object?>), AiFailure>{
      (401, {'error': 'unauthenticated'}): AiFailure.signedOut,
      (400, {'error': 'invalid-argument'}): AiFailure.invalid,
      (413, {'error': 'invalid-argument'}): AiFailure.invalid,
      (429, {'error': 'resource-exhausted', 'window': 'minute'}):
          AiFailure.rateLimited,
      (429, {'error': 'resource-exhausted', 'window': 'day'}):
          AiFailure.dailyLimit,
      (422, {'error': 'failed-precondition', 'blocked': true}):
          AiFailure.blocked,
      (404, {'error': 'not-found'}): AiFailure.notReady,
      (504, {'error': 'deadline-exceeded'}): AiFailure.timeout,
      (503, {'error': 'unavailable'}): AiFailure.unavailable,
      (500, {'error': 'internal'}): AiFailure.unavailable,
    };
    for (final MapEntry(key: (status, body), value: failure) in cases.entries) {
      final backend = service(
        (_) async => http.Response(jsonEncode(body), status),
      );
      expect(
        await failureOf(backend.askAiAssistant(userMessage: 'hi')),
        failure,
        reason: 'HTTP $status $body',
      );
    }
    // A 200 without a reply, or a page that is not JSON, is not an answer.
    expect(
      await failureOf(
        service((_) async => http.Response('{"reply": " "}', 200))
            .askAiAssistant(userMessage: 'hi'),
      ),
      AiFailure.unavailable,
    );
    expect(
      await failureOf(
        service((_) async => http.Response('<html>bad gateway</html>', 502))
            .askAiAssistant(userMessage: 'hi'),
      ),
      AiFailure.unavailable,
    );
  });

  test('offline and slow requests fail cleanly', () async {
    expect(
      await failureOf(
        service((_) async => throw http.ClientException('Failed host lookup'))
            .askAiAssistant(userMessage: 'hi'),
      ),
      AiFailure.unavailable,
    );
    expect(
      await failureOf(
        service(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 50),
        ).askAiAssistant(userMessage: 'hi'),
      ),
      AiFailure.timeout,
    );
  });
  test('attestation is sent with both answers and reports', () async {
    final requests = <http.Request>[];
    final backend = AiBackendService(
      endpoint: endpoint,
      idToken: () async => 'id-token',
      appCheckToken: () async => 'app-check-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'reply': 'ok', 'ok': true}), 200);
      }),
    );
    await backend.askAiAssistant(userMessage: 'hello');
    await backend.reportReply(reply: 'fixture', reason: 'incorrect');
    expect(requests.length, 2);
    for (final request in requests) {
      expect(request.headers['x-firebase-appcheck'], 'app-check-token');
      expect(request.headers['authorization'], 'Bearer id-token');
    }
  });

  test('consent withdrawn while attestation loads sends no question', () async {
    var requests = 0;
    var consent = true;
    final attestation = Completer<String?>();
    final started = Completer<void>();
    final backend = AiBackendService(
      endpoint: endpoint,
      idToken: () async => 'id-token',
      appCheckToken: () {
        started.complete();
        return attestation.future;
      },
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    final result = failureOf(
      backend.askAiAssistant(userMessage: 'private', allowed: () => consent),
    );
    await started.future;
    consent = false;
    attestation.complete('app-check-token');
    expect(await result, AiFailure.withdrawn);
    expect(requests, 0);
  });
}

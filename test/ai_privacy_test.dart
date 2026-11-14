import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/services/ai_backend_service.dart';
import 'package:focusforge/core/services/ai_privacy.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup expires persisted reports and sanitizes older retained reports',
    () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'ff.user': jsonEncode({
          'displayName': 'Sam Lee',
          'uid': 'account-identifier',
        }),
        'ff.assistant.reports': jsonEncode({
          'items': [
            {
              'at': now.subtract(const Duration(days: 91)).toIso8601String(),
              'reason': 'harmful',
              'reply': 'expired',
            },
            {
              'at': now.subtract(const Duration(days: 1)).toIso8601String(),
              'reason': 'incorrect',
              'reply': 'Sam Lee student@example.com',
            },
          ],
        }),
      });
      final store = await LocalStore.open();
      expect(store.getMap(StoreKeys.assistantReports)!['items'], hasLength(1));
      final persisted = store
          .exportAll()[StoreKeys.assistantReports]
          .toString();
      for (final value in ['Sam Lee', 'student@example.com', 'expired']) {
        expect(persisted, isNot(contains(value)));
      }
    },
  );
  test('identifiers and known profile values are removed without changing study totals', () {
    for (final value in [
      'student@example.com',
      'student@exam\u200bple.com',
      'com.instagram.android',
      '+91 (98765) 43210',
      '192.168.1.10',
      '123456789012345',
      'aabbccdd11223344',
      '12345678-1234-1234-1234-123456789012',
      'device_id: installation-12345',
      'https://school.example/student/name?token=private',
    ]) {
      expect(AiPrivacy.text(value), '[redacted]', reason: value);
    }
    expect(
      AiPrivacy.text(
        'Sam Lee studies the same topic.',
        privateValues: ['Sam Lee'],
      ),
      '[redacted] studies the same topic.',
    );
    expect(AiPrivacy.text('你好 李明', privateValues: ['李明']), '你好 [redacted]');
    expect(
      AiPrivacy.text('Study 25 minutes, rest 5 minutes.'),
      'Study 25 minutes, rest 5 minutes.',
    );
  });

  test('only bounded numeric study totals leave the client, including history and reports', () async {
    final requests = <http.Request>[];
    final backend = AiBackendService(
      endpoint: Uri.parse('https://pip.example.workers.dev/'),
      idToken: () async => 'fixture-token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'reply': 'Study in small blocks.'}),
          200,
        );
      }),
    );
    const privateText =
        'student@example.com com.instagram.android 123456789012345';
    await backend.askAiAssistant(
      userMessage: privateText,
      extraContext: {
        'todayMinutes': 25,
        'weekMinutes': 200000,
        'streak': -1,
        'exam': privateText,
        'subjects': [
          {'name': privateText},
        ],
        'distractingMinutesToday': 40,
      },
      history: const [
        {'role': 'user', 'text': privateText},
      ],
    );
    await backend.reportReply(
      reply: privateText,
      question: privateText,
      reason: 'harmful',
    );
    final body = jsonDecode(requests.first.body) as Map;
    expect(body['context'], {'todayMinutes': 25, 'weekMinutes': 100000});
    for (final request in requests) {
      expect(request.followRedirects, isFalse);
      for (final value in [
        'student@example.com',
        'com.instagram.android',
        '123456789012345',
        'distractingMinutesToday',
      ]) {
        expect(request.body, isNot(contains(value)));
      }
    }
  });

  test(
    'unsafe endpoint fails before acquiring or transmitting a credential',
    () async {
      var calls = 0;
      for (final url in [
        'http://pip.example/',
        'https://user:password@pip.example/',
      ]) {
        final backend = AiBackendService(
          endpoint: Uri.parse(url),
          idToken: () async {
            calls++;
            return 'private-token';
          },
        );
        await expectLater(
          backend.askAiAssistant(userMessage: 'help'),
          throwsA(isA<AiBackendException>()),
        );
        await expectLater(
          backend.reportReply(reply: 'help', reason: 'incorrect'),
          throwsA(isA<AiBackendException>()),
        );
      }
      expect(calls, 0);
    },
  );

  test('local review cache expires old, future and malformed reports and redacts retained content', () {
    final now = DateTime.utc(2026, 11, 14);
    final result = AiPrivacy.reports(
      {
        'items': [
          {
            'at': now.subtract(const Duration(days: 91)).toIso8601String(),
            'reason': 'harmful',
            'reply': 'expired',
          },
          {
            'at': now.add(const Duration(days: 1)).toIso8601String(),
            'reason': 'hate',
            'reply': 'future',
          },
          {'at': 'invalid', 'reason': 'hate', 'reply': 'invalid'},
          {
            'at': now.toIso8601String(),
            'reason': 'incorrect',
            'reply': 'student@example.com',
            'question': 'Sam Lee',
          },
        ],
      },
      now: now,
      privateValues: ['Sam Lee'],
    );
    expect(result['items'], hasLength(1));
    for (final value in ['expired', 'student@example.com', 'Sam Lee']) {
      expect(jsonEncode(result), isNot(contains(value)));
    }
  });
}

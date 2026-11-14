import 'dart:async';
import 'dart:convert';

import 'app_attestation.dart';
import 'ai_privacy.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Why an online answer could not be had.
enum AiFailure {
  /// No signed-in account: the proxy only answers signed-in users.
  signedOut,

  /// No network, or the proxy and both models could not be reached.
  unavailable,

  /// The answer took longer than the timeout.
  timeout,

  /// Too many questions in a short time.
  rateLimited,

  /// The day's allowance is used up.
  dailyLimit,

  /// The model's safety filters declined the question.
  blocked,

  /// The message was empty or unreadable.
  invalid,

  /// The proxy is not deployed or not configured in this build.
  notReady,

  /// Online answers were turned off, or the account left, before the
  /// question was sent: nothing left the phone.
  withdrawn,
}

@immutable
class AiBackendException implements Exception {
  const AiBackendException(this.failure, [this.detail]);

  final AiFailure failure;
  final String? detail;

  @override
  String toString() =>
      'AiBackendException($failure${detail == null ? '' : ': $detail'})';
}

/// Pip's online answers.
abstract interface class AiBackend {
  /// Sends [userMessage], with an optional study summary in [extraContext],
  /// and returns Pip's reply. Throws [AiBackendException] on any failure.
  ///
  /// [allowed] is asked once more right before the request is sent; when it
  /// says no, nothing is sent and [AiFailure.withdrawn] is thrown.
  Future<String> askAiAssistant({
    required String userMessage,
    Map<String, dynamic>? extraContext,
    List<Map<String, String>> history = const [],
    String locale = 'en',
    bool Function()? allowed,
  });

  /// Sends a user's report of [reply] for review. [reason] is one of
  /// [reportReasons]. Throws [AiBackendException] when it cannot be sent.
  Future<void> reportReply({
    required String reply,
    required String reason,
    String? question,
  });
}

/// Why an answer can be reported, as the worker accepts them.
const reportReasons = ['harmful', 'hate', 'incorrect'];

/// Returns the signed-in user's Firebase ID token, or null when signed out.
typedef IdTokenSource = Future<String?> Function();

/// Calls Pip's proxy, a Cloudflare Worker that holds the model keys.
///
/// The app never sees a key: the worker checks the caller's Firebase ID
/// token, bounds the request, applies a per-user rate limit and asks Gemini,
/// falling back to Groq. See `pip-ai-backend/`.
class AiBackendService implements AiBackend {
  AiBackendService({
    required this.endpoint,
    required this._idToken,
    http.Client? client,
    this._appCheckToken,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client();

  /// The deployed worker (`pip-ai-backend/`). A build can point elsewhere
  /// with `--dart-define=PIP_AI_URL=https://…`, or turn online answers off
  /// with an empty value.
  static const defaultEndpoint = String.fromEnvironment(
    'PIP_AI_URL',
    defaultValue: 'https://pip-ai-backend.pip-ai-backend.workers.dev/',
  );

  /// The worker cuts messages here too; trimming first keeps requests small.
  static const maxMessageChars = 300;

  final Uri endpoint;
  final IdTokenSource _idToken;
  final IdTokenSource? _appCheckToken;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<String> askAiAssistant({
    required String userMessage,
    Map<String, dynamic>? extraContext,
    List<Map<String, String>> history = const [],
    String locale = 'en',
    bool Function()? allowed,
  }) async {
    _requireHttps();
    final message = AiPrivacy.text(userMessage, maxChars: maxMessageChars);
    if (message.isEmpty) {
      throw const AiBackendException(AiFailure.invalid, 'Empty message');
    }
    final String? token;
    try {
      token = await _idToken();
    } catch (error) {
      throw AiBackendException(AiFailure.signedOut, '$error');
    }
    if (token == null || token.isEmpty) {
      throw const AiBackendException(AiFailure.signedOut);
    }
    final attestation = await _appCheckToken?.call();
    // Getting a token can take a while; consent may be gone by now.
    if (allowed != null && !allowed()) {
      throw const AiBackendException(AiFailure.withdrawn);
    }

    final http.Response response;
    try {
      response = await _post(
        endpoint,
        headers: {
          'authorization': 'Bearer $token',
          'x-firebase-appcheck': ?attestation,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'message': message.length > maxMessageChars
              ? message.substring(0, maxMessageChars)
              : message,
          'context': AiPrivacy.studyContext(extraContext),
          'history': [
            for (final turn in history.skip(
              history.length > 8 ? history.length - 8 : 0,
            ))
              {
                'role': turn['role'] == 'pip' ? 'pip' : 'user',
                'text': AiPrivacy.text(turn['text'] ?? ''),
              },
          ],
          'locale': locale,
        }),
      ).timeout(timeout);
    } on TimeoutException {
      throw const AiBackendException(AiFailure.timeout);
    } catch (error) {
      // Offline, DNS failure, connection reset: the phone answers instead.
      throw AiBackendException(AiFailure.unavailable, '$error');
    }

    final body = _decode(response.body);
    if (response.statusCode == 200) {
      final reply = body['reply'];
      if (reply is String && reply.trim().isNotEmpty) return reply.trim();
      throw const AiBackendException(AiFailure.unavailable, 'Empty reply');
    }
    throw AiBackendException(
      failureFor(response.statusCode, body),
      'HTTP ${response.statusCode} ${body['error'] ?? ''}'.trim(),
    );
  }

  @override
  Future<void> reportReply({
    required String reply,
    required String reason,
    String? question,
  }) async {
    _requireHttps();
    final token = await _idToken().catchError((_) => null);
    if (token == null || token.isEmpty) {
      throw const AiBackendException(AiFailure.signedOut);
    }
    final attestation = await _appCheckToken?.call();
    final http.Response response;
    try {
      response = await _post(
        endpoint.resolve('report'),
        headers: {
          'authorization': 'Bearer $token',
          'x-firebase-appcheck': ?attestation,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'reason': reason,
          'reply': AiPrivacy.text(reply, maxChars: 900),
          if (question != null)
            'question': AiPrivacy.text(question, maxChars: 300),
        }),
      ).timeout(timeout);
    } on TimeoutException {
      throw const AiBackendException(AiFailure.timeout);
    } catch (error) {
      throw AiBackendException(AiFailure.unavailable, '$error');
    }
    if (response.statusCode != 200) {
      throw AiBackendException(
        failureFor(response.statusCode, _decode(response.body)),
      );
    }
  }

  void _requireHttps() {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const AiBackendException(AiFailure.notReady);
    }
  }

  Future<http.Response> _post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    // Never forward credentials or private text to a redirected host or URL.
    final request = http.Request('POST', url)
      ..followRedirects = false
      ..headers.addAll(headers)
      ..body = body;
    return http.Response.fromStream(await _client.send(request));
  }

  static Map<String, Object?> _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, Object?> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Maps the worker's HTTP status and error body to a failure.
  @visibleForTesting
  static AiFailure failureFor(int status, Map<String, Object?> body) =>
      switch (status) {
        401 || 403 => AiFailure.signedOut,
        400 || 413 => AiFailure.invalid,
        429 =>
          body['window'] == 'day'
              ? AiFailure.dailyLimit
              : AiFailure.rateLimited,
        422 => body['blocked'] == true ? AiFailure.blocked : AiFailure.invalid,
        404 || 405 => AiFailure.notReady,
        504 => AiFailure.timeout,
        // 500, 502, 503 and anything unexpected.
        _ => AiFailure.unavailable,
      };
}

/// The online backend, or null when this build has no proxy configured.
/// Overridden in tests with a fake.
final aiBackendProvider = Provider<AiBackend?>((ref) {
  final endpoint = Uri.tryParse(AiBackendService.defaultEndpoint);
  if (endpoint == null ||
      endpoint.scheme != 'https' ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty) {
    return null;
  }
  return AiBackendService(
    endpoint: endpoint,
    // Throws where Firebase is not set up, which reads as signed out.
    idToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    appCheckToken: appAttestationToken,
  );
});

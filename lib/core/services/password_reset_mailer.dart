import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_attestation.dart';

/// What FocusForge's reset email service answered.
enum ResetMailResult { sent, invalidEmail, rateLimited, unavailable }

/// Sends a password reset email for an address.
typedef PasswordResetMailer = Future<ResetMailResult> Function(String email);

/// Rate-limited branded reset request. The website durably queues all addresses
/// alike, then sends the FocusForge email after the public response.
const passwordResetEndpoint = 'https://www.focus-forge.in/api/password-reset';

/// Posts [email] to [passwordResetEndpoint]. Any network failure, timeout or
/// unexpected answer is [ResetMailResult.unavailable], which the caller treats
/// as "use Firebase's own email instead".
Future<ResetMailResult> sendFocusForgeResetEmail(
  String email, {
  HttpClient? client,
  Future<String?> Function()? appCheckToken,
}) async {
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final attestation = await (appCheckToken ?? appAttestationToken)();
    final request = await http
        .postUrl(Uri.parse(passwordResetEndpoint))
        .timeout(const Duration(seconds: 10));
    request.headers.contentType = ContentType.json;
    if (attestation != null) {
      request.headers.set('X-Firebase-AppCheck', attestation);
    }
    request.write(jsonEncode({'email': email}));
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    return switch (response.statusCode) {
      200 => ResetMailResult.sent,
      400 => ResetMailResult.invalidEmail,
      429 => ResetMailResult.rateLimited,
      _ => ResetMailResult.unavailable,
    };
  } catch (_) {
    return ResetMailResult.unavailable;
  } finally {
    if (client == null) http.close();
  }
}

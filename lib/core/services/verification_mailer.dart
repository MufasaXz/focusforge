import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_attestation.dart';

/// What FocusForge's verification email service answered.
enum VerificationMailResult { sent, invalidEmail, rateLimited, unavailable }

/// Sends a verification email for the signed-in account.
typedef VerificationMailer = Future<VerificationMailResult> Function(
  String idToken,
);

/// Rate-limited branded verification request. The recipient is derived on the server from the Firebase credential.
const verificationEmailEndpoint =
    'https://www.focus-forge.in/api/verification-email';

/// Posts an authenticated request to [verificationEmailEndpoint]. Any network failure, timeout or
/// unexpected answer is [VerificationMailResult.unavailable], which the caller treats
/// as "use Firebase's own email instead".
Future<VerificationMailResult> sendFocusForgeVerificationEmail(
  String idToken, {
  HttpClient? client,
  Future<String?> Function()? appCheckToken,
}) async {
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final attestation = await (appCheckToken ?? appAttestationToken)();
    final request = await http
        .postUrl(Uri.parse(verificationEmailEndpoint))
        .timeout(const Duration(seconds: 10));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $idToken');
    if (attestation != null) {
      request.headers.set('X-Firebase-AppCheck', attestation);
    }
    request.write(jsonEncode(<String, Object>{}));
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    return switch (response.statusCode) {
      200 => VerificationMailResult.sent,
      400 => VerificationMailResult.invalidEmail,
      429 => VerificationMailResult.rateLimited,
      _ => VerificationMailResult.unavailable,
    };
  } catch (_) {
    return VerificationMailResult.unavailable;
  } finally {
    if (client == null) http.close();
  }
}

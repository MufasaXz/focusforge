import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What FocusForge's reset email service answered.
enum ResetMailResult { sent, invalidEmail, rateLimited, unavailable }

/// Sends a password reset email for an address.
typedef PasswordResetMailer = Future<ResetMailResult> Function(String email);

/// FocusForge's own reset email, sent by the website.
///
/// Firebase will not let this project change its reset email, so the website
/// makes the one-time code with the Admin SDK and sends an email whose button
/// opens the FocusForge reset page. It answers the same for addresses with and
/// without an account.
const passwordResetEndpoint = 'https://www.focus-forge.in/api/password-reset';

/// Posts [email] to [passwordResetEndpoint]. Any network failure, timeout or
/// unexpected answer is [ResetMailResult.unavailable], which the caller treats
/// as "use Firebase's own email instead".
Future<ResetMailResult> sendFocusForgeResetEmail(
  String email, {
  HttpClient? client,
}) async {
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await http
        .postUrl(Uri.parse(passwordResetEndpoint))
        .timeout(const Duration(seconds: 10));
    request.headers.contentType = ContentType.json;
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

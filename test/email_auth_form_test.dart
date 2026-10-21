import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/shared/widgets/email_auth_sheet.dart';
import 'package:focusforge/shared/widgets/form_controls.dart';

class _EmailAuth extends LocalAuthService {
  _EmailAuth(super.store);
  final signups = <(String, String)>[];
  final requests = <String>[];
  Completer<void>? pendingRequest;
  bool failRequest = false;

  @override
  bool get usesRemoteCredentials => true;

  @override
  Future<UserProfile> signUpWithEmail(String email, String password) async {
    signups.add((email, password));
    throw const AuthException(AuthFailure.emailVerificationRequired);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    requests.add(email);
    if (failRequest) {
      throw const AuthException(AuthFailure.providerUnavailable);
    }
    await pendingRequest?.future;
  }
}

void main() {
  late _EmailAuth auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    auth = _EmailAuth(await LocalStore.open());
  });
  tearDown(() => auth.dispose());

  Future<void> showForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: EmailAuthSheet(service: auth)),
      ),
    );
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PrimaryAction>(find.widgetWithText(PrimaryAction, label))
      .enabled;

  testWidgets('signup requires matching confirmation and shows strength', (
    tester,
  ) async {
    await showForm(tester);
    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Forgot password?'), findsNothing);
    await tester.enterText(
      find.byType(TextField).at(0),
      ' person@example.com ',
    );
    await tester.enterText(find.byType(TextField).at(1), 'LongPassword12!');
    await tester.pumpAndSettle();
    expect(find.text('Strong'), findsOneWidget);
    expect(enabled(tester, 'Create account'), isFalse);
    await tester.enterText(find.byType(TextField).at(2), 'different');
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(enabled(tester, 'Create account'), isFalse);
    await tester.enterText(find.byType(TextField).at(2), 'LongPassword12!');
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(auth.signups, [('person@example.com', 'LongPassword12!')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset sends a Firebase link and explains the hosted page', (
    tester,
  ) async {
    await showForm(tester);
    await tester.enterText(
      find.byType(TextField).first,
      ' person@example.com ',
    );
    await tester.enterText(find.byType(TextField).last, 'old-password');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(auth.requests, ['person@example.com']);
    expect(find.textContaining('a reset link is on its way'), findsOneWidget);
    expect(find.textContaining('Firebase’s secure page'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'other@example.com');
    await tester.pump();
    expect(find.textContaining('a reset link is on its way'), findsNothing);
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with email'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'requesting a reset prevents duplicate sends and editing the address',
    (tester) async {
      await showForm(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'person@example.com',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      auth.pendingRequest = Completer<void>();
      await tester.tap(find.text('Send reset link'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      expect(auth.requests, ['person@example.com']);
      auth.pendingRequest!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in with email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable reset email never claims a link was sent', (
    tester,
  ) async {
    await showForm(tester);
    await tester.enterText(find.byType(TextField).first, 'person@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    auth.failRequest = true;
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
    expect(find.text('Six-digit code'), findsNothing);
    expect(find.textContaining('a reset link is on its way'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup and reset remain usable at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: EmailAuthSheet(service: auth)),
      ),
    );
    await tester.ensureVisible(find.text('Create an account instead'));
    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'LongPassword12!');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('I already have an account'));
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send reset link'));
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    ScaffoldMessenger.of(tester.element(find.byType(EmailAuthSheet)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Back to sign in'));
    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with email'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/bootstrap.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/firebase_auth_service.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_backup_service.dart';
import 'package:focusforge/core/services/profile_photo.dart';
import 'package:image/image.dart' as img;

import 'dart:typed_data';

class _RemoteUser implements User {
  @override
  String get uid => 'returning-user';
  @override
  String get displayName => 'Alex';
  @override
  String get email => 'alex@example.com';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  AdditionalUserInfo? get additionalUserInfo => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RemoteAuth implements FirebaseAuth {
  User? user = _RemoteUser();
  final controller = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => controller.stream;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    user = _RemoteUser();
    controller.add(user);
    return _Credential(user!);
  }

  @override
  Future<void> signOut() async {
    user = null;
    controller.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backup implements StudyBackupBackend {
  StudyBackup? saved;
  @override
  Future<StudyBackup?> load(String uid) async => saved;
  @override
  Future<void> save(String uid, StudyBackup backup) async => saved = backup;
}

class _Board implements LeaderboardService {
  final rows = StreamController<List<BoardRow>>.broadcast();
  List<BoardRow> current = [];
  @override
  bool get available => true;
  @override
  String? get uid => 'returning-user';
  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) async* {
    yield current;
    yield* rows.stream;
  }

  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
    required int level,
    String? avatarPhoto,
  }) async {
    current = [
      BoardRow(
        uid: uid,
        name: name,
        minutes: minutes,
        level: level,
        avatarPhoto: avatarPhoto,
      ),
    ];
    rows.add(current);
  }

  @override
  Future<void> withdraw(String week, String uid) async {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restoring a real credential hydrates weekly score, consent and own-row recognition', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    const account = UserProfile(
      uid: 'returning-user',
      displayName: 'Alex',
      isAnonymous: false,
      onboardingComplete: true,
      dailyGoalMinutes: 480,
    );
    // An older build retained the signed-out account on this device without
    // the private-backup revision introduced by the newer build.
    await store.setMap(
      StoreKeys.user,
      account.copyWith(isAnonymous: true).toJson(),
    );
    await store.setBool(StoreKeys.boardOptIn, false);
    final backup = _Backup()
      ..saved = StudyBackup(
        settings: {
          StoreKeys.user: jsonEncode(account.toJson()),
          StoreKeys.boardOptIn: true,
          StoreKeys.dailyGoal: 480,
          StoreKeys.planLibrary: jsonEncode({
            'version': 1,
            'plans': [
              const CustomPlan(
                id: 'exam-plan',
                name: 'Exam revision',
                focusMinutes: 40,
                goalMinutes: 120,
              ).toJson(),
            ],
          }),
        },
        sessions: [
          FocusSession(
            id: 'earlier-today',
            subjectId: 'math',
            ownerUid: 'returning-user',
            startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
            minutes: 300,
          ).toJson(),
        ],
        modifiedAt: DateTime.now().millisecondsSinceEpoch,
      );
    final remoteAuth = _RemoteAuth();
    final auth = FirebaseAuthService(
      store,
      firebaseAuth: remoteAuth,
      studyBackup: StudyBackupService(store, backup),
    );
    final board = _Board();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
        leaderboardServiceProvider.overrideWithValue(board),
      ],
    );
    final bridge = auth.changes.listen((profile) {
      if (profile != null) {
        hydrateStudyAccount(container, store);
        container.read(userProvider.notifier).hydrate(profile);
      } else if (!auth.signedIn) {
        final local = container.read(userProvider);
        container
            .read(userProvider.notifier)
            .hydrate(local.copyWith(isAnonymous: true));
      }
    });
    addTearDown(() async {
      await bridge.cancel();
      container.dispose();
      auth.dispose();
      await remoteAuth.controller.close();
      await board.rows.close();
    });
    container.read(leaderboardPublisherProvider);
    final boardSubscription = container.listen(weekBoardProvider, (_, _) {});
    addTearDown(boardSubscription.close);
    await auth.restore();
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    await container.read(boardPublishQueueProvider).run(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountUidProvider), 'returning-user');
    expect(container.read(boardOptInProvider), isTrue);
    expect(container.read(leaderboardWeekHoursProvider), 5);
    expect(container.read(myRankProvider)?.uid, 'returning-user');
    expect(container.read(myRankProvider)?.isMe, isTrue);
    expect(container.read(planLibraryProvider).plans.single.id, 'exam-plan');

    final photo = ProfilePhoto.encode(
      Uint8List.fromList(img.encodePng(img.Image(width: 32, height: 32))),
    );
    await container.read(userProvider.notifier).setDisplayName('Alex Updated');
    await container.read(userProvider.notifier).setPhoto(photo);
    await container.pump();
    await container.read(boardPublishQueueProvider).run(() async {});
    expect(board.current.single.name, 'Alex Updated');
    expect(board.current.single.avatarPhoto, photo);

    await auth.signOut();
    await container
        .read(userProvider.notifier)
        .save(container.read(userProvider).copyWith(isAnonymous: true));
    await container.pump();
    expect(container.read(accountUidProvider), isNull);
    expect(board.current.single.minutes, 300);
    await auth.signInWithEmail('alex@example.com', 'password');
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    await container.read(boardPublishQueueProvider).run(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountUidProvider), 'returning-user');
    expect(container.read(leaderboardWeekHoursProvider), 5);
    expect(container.read(boardOptInProvider), isTrue);
    expect(container.read(myRankProvider)?.isMe, isTrue);
    expect(container.read(planLibraryProvider).plans.single.id, 'exam-plan');
    expect(container.read(userProvider).displayName, 'Alex Updated');
    expect(container.read(userProvider).avatarPhoto, photo);
    expect(board.current.single.name, 'Alex Updated');
    expect(board.current.single.avatarPhoto, photo);
  });
}

// The parent's security code, and the one thing it guards that is not a screen:
// whether a rule set on another phone is actually enforced here.
//
// WHAT INVARIANT: a linked parent plus a code means the shield asks for the
// code before a rule changes, and "watching only" means the parent's list is
// stored but never reaches the engine.
//
// WHY IT MATTERS: the code is the only thing standing between a child and the
// rules their parent set, and the enforcement flag is what makes "I am just
// watching for now" mean something. If either leaked — a rule that applied
// while enforcement was off, or a code that verified a wrong value — the
// parent's setup would be decoration.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/parent.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/parent_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/parent_service.dart';
import 'package:focusforge/core/services/shield_service.dart';

/// A backend that is already paired, so the child's side has something to
/// react to without a network.
class PairedParentService implements ParentService {
  PairedParentService({required this.blocks});

  RemoteBlocks blocks;

  @override
  bool get available => true;

  @override
  String? get uid => 'child-1';

  @override
  Stream<List<ChildLink>> watchChildren(String parentUid) =>
      Stream.value(const []);

  @override
  Stream<GuardianLink?> watchGuardian(String uid) =>
      Stream.value(GuardianLink(uid: 'parent-1', name: 'Amma'));

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) =>
      Stream.value(blocks);

  @override
  Stream<List<CatalogApp>> watchCatalog(String childUid) =>
      Stream.value(const []);

  @override
  Future<PairCode> mintPairCode({required String childName}) async =>
      PairCode(
        code: '123456',
        expiresAt: DateTime.now().add(PairCode.lifetime),
      );

  @override
  Future<ChildLink> linkChild(String code, {required String parentName}) async =>
      const ChildLink(uid: 'child-2', name: 'Ravi');

  @override
  Future<void> unlink(String uid) async {}

  @override
  Future<void> publishProgress(String uid, ChildProgress progress) async {}

  @override
  Stream<ChildProgress?> watchProgress(String childUid) => Stream.value(null);

  @override
  Future<void> publishBlocks(String childUid, RemoteBlocks blocks) async {}

  @override
  Future<void> publishCatalog(String uid, List<CatalogApp> apps) async {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
  });

  ProviderContainer childDevice(
    ShieldPlatformService engine, {
    ParentService? parent,
  }) {
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        if (parent != null) parentServiceProvider.overrideWithValue(parent),
      ],
    );
    addTearDown(container.dispose);
    // A linked device has an account id; the app's own uid is what the rules
    // and the streams are keyed on.
    container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'child-1', displayName: 'Ravi'));
    return container;
  }

  test('the code is stored as a hash and verified, never kept as digits', () async {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final codes = container.read(securityCodeProvider.notifier);

    expect(container.read(securityCodeProvider), isFalse);
    await codes.set('4821');
    expect(container.read(securityCodeProvider), isTrue);

    final stored = store.getString(StoreKeys.parentSecurity)!;
    expect(stored.contains('4821'), isFalse);
    expect(stored.contains(':'), isTrue);

    expect(codes.verify('4821'), isTrue);
    expect(codes.verify('4822'), isFalse);
    expect(codes.verify(''), isFalse);

    await codes.clear();
    expect(container.read(securityCodeProvider), isFalse);
    expect(codes.verify('4821'), isFalse);
  });

  test('a code is only asked for on a linked device that has one', () async {
    final container = childDevice(
      RecordingShieldService(),
      parent: PairedParentService(blocks: const RemoteBlocks()),
    );

    // The guardian stream has to have delivered before the link is real.
    await container.read(guardianProvider.future);
    expect(container.read(parentLockedProvider), isFalse);

    // Linked but no code: nothing to ask for.
    expect(container.read(securityCodeProvider), isFalse);
    expect(container.read(parentLockedProvider), isFalse);

    await container.read(securityCodeProvider.notifier).set('4821');
    expect(container.read(parentLockedProvider), isTrue);

    // Entered once for this run.
    container.read(parentLockProvider.notifier).open();
    expect(container.read(parentLockedProvider), isFalse);
  });

  test('a parent\'s blocks reach the engine, and watching does not', () async {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = childDevice(
      engine,
      parent: PairedParentService(
        blocks: const RemoteBlocks(
          apps: [
            RemoteBlock(packageId: 'com.instagram.android', name: 'Instagram'),
          ],
        ),
      ),
    );

    container.read(shieldSyncBridgeProvider);
    await container.read(myRemoteBlocksProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(engine.lastApplied, isNotNull);
    expect(
      engine.lastApplied!.remote.map((r) => r.packageId),
      contains('com.instagram.android'),
    );

    // Watching only: the list is still there, and nothing is enforced.
    expect(
      const RemoteBlocks(
        apps: [RemoteBlock(packageId: 'com.instagram.android', name: 'I')],
        enforced: false,
      ).inForce.isEmpty,
      isTrue,
    );
  });
}

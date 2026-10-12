import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/parent.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/parent_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/parent_service.dart';

class _PrivateFamilyBackend extends UnavailableParentService {
  final children = <String, StreamController<List<ChildLink>>>{};
  final progress = StreamController<ChildProgress>.broadcast();
  final blocks = StreamController<RemoteBlocks>.broadcast();
  final catalog = StreamController<List<CatalogApp>>.broadcast();
  final guardian = StreamController<GuardianLink>.broadcast();
  int privateReads = 0;

  @override
  bool get available => true;

  @override
  Stream<List<ChildLink>> watchChildren(String parentUid) => children
      .putIfAbsent(
        parentUid,
        () => StreamController<List<ChildLink>>.broadcast(),
      )
      .stream;

  @override
  Stream<ChildProgress> watchProgress(String childUid) {
    privateReads++;
    return progress.stream;
  }

  @override
  Stream<RemoteBlocks> watchBlocks(String childUid) {
    privateReads++;
    return blocks.stream;
  }

  @override
  Stream<List<CatalogApp>> watchCatalog(String childUid) {
    privateReads++;
    return catalog.stream;
  }

  @override
  Stream<GuardianLink> watchGuardian(String childUid) {
    privateReads++;
    return guardian.stream;
  }

  Future<void> close() async {
    await Future.wait([
      for (final controller in children.values) controller.close(),
      progress.close(),
      blocks.close(),
      catalog.close(),
      guardian.close(),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;
  late _PrivateFamilyBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    backend = _PrivateFamilyBackend();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        parentServiceProvider.overrideWithValue(backend),
      ],
    );
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'parent-one'));
  });

  tearDown(() async {
    container.dispose();
    await backend.close();
  });

  void watchFamilies() {
    container.listen(childProgressProvider('child'), (_, _) {});
    container.listen(childBlocksProvider('child'), (_, _) {});
    container.listen(childCatalogProvider('child'), (_, _) {});
    container.listen(childGuardianProvider('child'), (_, _) {});
  }

  Future<void> tick() => container.pump();

  Future<void> loadPrivateRows() async {
    container.listen(childrenProvider, (_, _) {});
    watchFamilies();
    await tick();
    backend.children['parent-one']?.add(const [
      ChildLink(uid: 'child', name: 'Ari'),
    ]);
    await tick();
    expect(container.read(childrenProvider).asData?.value, hasLength(1));
    expect(container.read(childrenProvider).isLoading, isFalse);
    expect(container.read(accountUidProvider), 'parent-one');
    container.read(childProgressProvider('child'));
    container.read(childBlocksProvider('child'));
    container.read(childCatalogProvider('child'));
    container.read(childGuardianProvider('child'));
    expect(backend.privateReads, 4);
    expect(backend.progress.hasListener, isTrue);
    backend.progress.add(const ChildProgress(minutes: 73));
    backend.blocks.add(
      const RemoteBlocks(
        apps: [RemoteBlock(packageId: 'private.app', name: 'Private')],
      ),
    );
    backend.catalog.add(const [
      CatalogApp(packageId: 'private.app', name: 'Private'),
    ]);
    backend.guardian.add(
      GuardianLink(
        uid: 'parent-one',
        name: 'Ari parent',
        code: ParentCode.of('1234'),
      ),
    );
    await tick();
    expect(
      container.read(childProgressProvider('child')).valueOrNull?.minutes,
      73,
    );
    expect(
      container.read(childCatalogProvider('child')).valueOrNull,
      hasLength(1),
    );
    expect(
      container.read(childGuardianProvider('child')).valueOrNull?.code,
      isNotNull,
    );
  }

  void expectPrivateRowsCleared() {
    expect(container.read(childProgressProvider('child')).valueOrNull, isNull);
    expect(container.read(childBlocksProvider('child')).valueOrNull, isNull);
    expect(
      container.read(childCatalogProvider('child')).valueOrNull ?? [],
      isEmpty,
    );
    expect(container.read(childGuardianProvider('child')).valueOrNull, isNull);
  }

  test('private family reads require a confirmed current child link', () async {
    watchFamilies();
    await tick();
    expect(backend.privateReads, 0);
    expectPrivateRowsCleared();
  });

  test('account switch clears retained private rows before the new link list arrives', () async {
    await loadPrivateRows();
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'parent-two'));
    expectPrivateRowsCleared();
    await tick();
    expectPrivateRowsCleared();
    backend.progress.add(const ChildProgress(minutes: 99));
    await tick();
    expectPrivateRowsCleared();
  });

  test('signout clears retained private rows immediately', () async {
    await loadPrivateRows();
    container.read(userProvider.notifier).hydrate(const UserProfile());
    expectPrivateRowsCleared();
    await tick();
    expectPrivateRowsCleared();
  });

  test('confirmed unlink clears every private family', () async {
    await loadPrivateRows();
    backend.children['parent-one']!.add(const []);
    await tick();
    expectPrivateRowsCleared();
  });

  test('an unconfirmed link list never displays retained child data', () async {
    await loadPrivateRows();
    container.invalidate(childrenProvider);
    expectPrivateRowsCleared();
    await tick();
    expectPrivateRowsCleared();
  });
}

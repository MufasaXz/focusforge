// Which apps reach the Shield's list.
//
// WHAT INVARIANT: the list is the apps the user can open, minus the ones the
// engine refuses to cover, plus anything that already carries a rule — and a
// system flag on its own never removes a row.
//
// WHY IT MATTERS: the list *is* the feature. An app missing from it cannot be
// restricted at all, and nothing on screen says why. The filter used to be
// `isSystem`, which was correct while the app held QUERY_ALL_PACKAGES and saw
// every service and vendor stub on the device. Once the manifest narrowed to
// a `<queries>` declaration the same filter started hiding preinstalled
// browsers, mail clients and video apps — system apps with launcher icons,
// and most of what a student actually wants to close.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';

const _device = <InstalledApp>[
  // Preinstalled, with a launcher icon. The case the old filter dropped.
  InstalledApp(packageId: 'com.android.chrome', name: 'Chrome', isSystem: true),
  // Preinstalled, no launcher icon: a service the user cannot open.
  InstalledApp(
    packageId: 'com.android.vending.stub',
    name: 'Store stub',
    isSystem: true,
  ),
  // Installed by the user.
  InstalledApp(packageId: 'com.whatsapp', name: 'WhatsApp', isSystem: false),
  // The launcher. Openable, but the engine will not cover it.
  InstalledApp(packageId: 'com.android.launcher', name: 'Home', isSystem: true),
];

const _launchable = {'com.android.chrome', 'com.whatsapp', 'com.android.launcher'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  test('a preinstalled app with a launcher icon is offered', () async {
    // Resolve the overridden futures before the synchronous read.
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        installedAppsProvider.overrideWith((ref) async => _device),
        protectedPackagesProvider.overrideWith(
          (ref) async => {'com.android.launcher'},
        ),
        launchablePackagesProvider.overrideWith((ref) async => _launchable),
      ],
    );
    addTearDown(container.dispose);
    await container.read(installedAppsProvider.future);
    await container.read(protectedPackagesProvider.future);
    await container.read(launchablePackagesProvider.future);

    final names = [
      for (final row in container.read(shieldAppRowsProvider)) row.name,
    ];

    // Chrome is a system app. It is also the browser the user opens, so it
    // belongs on the list.
    expect(names, contains('Chrome'));
    expect(names, contains('WhatsApp'));
    // Nothing the user cannot open, and nothing the engine will not cover.
    expect(names, isNot(contains('Store stub')));
    expect(names, isNot(contains('Home')));
  });

  test('an engine that cannot answer falls back rather than emptying', () async {
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        installedAppsProvider.overrideWith((ref) async => _device),
        protectedPackagesProvider.overrideWith(
          (ref) async => {'com.android.launcher'},
        ),
        // No launcher answer: an older engine, or a platform without one.
        launchablePackagesProvider.overrideWith((ref) async => const <String>{}),
      ],
    );
    addTearDown(container.dispose);
    await container.read(installedAppsProvider.future);
    await container.read(protectedPackagesProvider.future);
    await container.read(launchablePackagesProvider.future);

    final names = [
      for (final row in container.read(shieldAppRowsProvider)) row.name,
    ];

    // The previous filter, so the screen still shows the user's own apps
    // instead of going blank.
    expect(names, ['WhatsApp']);
  });
}

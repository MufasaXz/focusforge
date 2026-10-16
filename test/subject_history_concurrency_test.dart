import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retaining a deleted subject name preserves simultaneous completed sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final sessions = container.read(sessionsProvider.notifier);
    await sessions.record(
      FocusSession(
        id: 'old',
        subjectId: 'math',
        startedAt: DateTime.now(),
        minutes: 25,
      ),
    );
    final retaining = sessions.retainSubjectName('math', 'Math');
    final recording = sessions.record(
      FocusSession(
        id: 'new',
        subjectId: '',
        startedAt: DateTime.now(),
        minutes: 25,
      ),
    );
    await Future.wait([retaining, recording]);
    expect(container.read(sessionsProvider).map((s) => s.id), ['old', 'new']);
    expect(store.getList(StoreKeys.sessions).map((s) => s['id']), [
      'old',
      'new',
    ]);
    expect(store.getList(StoreKeys.sessions).first['label'], 'Math');
  });
}

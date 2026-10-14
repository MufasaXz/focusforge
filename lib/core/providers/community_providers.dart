import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// Account-scoped local hiding; no blocked-user list is uploaded.
class BlockedCommunityUsers extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final uid = ref.watch(userProvider.select((u) => u.uid));
    final rows = ref.read(localStoreProvider).getList('community.blocks');
    return {
      for (final row in rows)
        if (row['owner'] == uid && row['uid'] is String) row['uid'] as String,
    };
  }

  Future<void> block(String uid) async {
    if (uid.isEmpty) return;
    final owner = ref.read(userProvider).uid;
    final store = ref.read(localStoreProvider);
    final rows = store.getList('community.blocks');
    state = {...state, uid};
    await store.setList('community.blocks', [
      for (final row in rows)
        if (row['owner'] != owner) row,
      for (final blocked in state) {'owner': owner, 'uid': blocked},
    ]);
  }
}

final blockedCommunityUsersProvider =
    NotifierProvider<BlockedCommunityUsers, Set<String>>(
      BlockedCommunityUsers.new,
    );

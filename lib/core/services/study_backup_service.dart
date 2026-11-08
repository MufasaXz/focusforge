import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import 'local_store.dart';

/// One account's data, either as this device holds it or as the cloud does.
///
/// The on-device copy carries everything. The cloud copy carries only
/// [StudyBackupService.cloudKeys] and no sessions: study history stays local.
/// [sessions] is still read from the cloud so that rows an older build uploaded
/// can move back to the device once, and then be deleted there.
class StudyBackup {
  const StudyBackup({
    required this.settings,
    required this.sessions,
    required this.modifiedAt,
    this.hasSettings = true,
  });
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> sessions;
  final int modifiedAt;
  final bool hasSettings;
  Map<String, dynamic> toJson() => {
    'settings': settings,
    'sessions': sessions,
    'modifiedAt': modifiedAt,
    'hasSettings': hasSettings,
  };
  static StudyBackup? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['settings'] is! Map) return null;
    return StudyBackup(
      settings: Map<String, dynamic>.from(json['settings'] as Map),
      sessions: (json['sessions'] as List? ?? [])
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList(),
      modifiedAt: json['modifiedAt'] is int ? json['modifiedAt'] as int : 0,
      hasSettings: json['hasSettings'] != false,
    );
  }
}

abstract class StudyBackupBackend {
  Future<StudyBackup?> load(String uid);
  Future<void> save(String uid, StudyBackup backup);
}

class FirebaseStudyBackupBackend implements StudyBackupBackend {
  FirebaseStudyBackupBackend(this.db);
  final FirebaseFirestore db;

  /// The settings document as last read or written, so a save that changes
  /// nothing — a finished session changes only local keys — costs no write.
  final _savedSettings = <String, String>{};

  /// Document ids of session rows an older build uploaded, by account.
  ///
  /// Only ids this backend has actually returned from [load] are ever deleted.
  /// By then the service has merged them into the device, so a row that
  /// arrives afterwards waits for the next load rather than being lost.
  final _legacySessions = <String, Set<String>>{};
  static const _wait = Duration(seconds: 12);
  DocumentReference<Map<String, dynamic>> _settings(String uid) =>
      db.doc('users/$uid/preferences/studyBackup');
  CollectionReference<Map<String, dynamic>> _sessions(String uid) =>
      db.collection('users/$uid/sessionData');
  @override
  Future<StudyBackup?> load(String uid) async {
    final config = await _settings(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(_wait);
    final rows = <Map<String, dynamic>>[];
    final legacy = <String>{};
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    while (true) {
      Query<Map<String, dynamic>> query = _sessions(uid)
          .orderBy(FieldPath.documentId);
      if (last != null) query = query.startAfterDocument(last);
      final page = await query
          .limit(400)
          .get(const GetOptions(source: Source.server))
          .timeout(_wait);
      for (final doc in page.docs) {
        final row = doc.data();
        if (row['ownerUid'] == uid && row['id'] is String) {
          rows.add(row);
          legacy.add(doc.id);
        }
      }
      if (page.docs.length < 400) break;
      last = page.docs.last;
    }
    _legacySessions[uid] = legacy;
    if (!config.exists && rows.isEmpty) return null;
    final data = config.data();
    Map<String, dynamic> settings = {};
    var hasSettings = false;
    try {
      final encoded = data?['data'];
      final decoded = encoded is String ? jsonDecode(encoded) : null;
      if (decoded is Map<String, dynamic>) {
        settings = decoded;
        hasSettings = true;
        _savedSettings[uid] = '${data?['modifiedAt']}:$encoded';
      }
    } on FormatException {
      /* A corrupt config must not erase valid sessions. */
    }
    return StudyBackup(
      settings: settings,
      sessions: rows,
      modifiedAt: data?['modifiedAt'] as int? ?? 0,
      hasSettings: hasSettings,
    );
  }

  /// Writes the settings document, then removes legacy session rows.
  ///
  /// [StudyBackup.sessions] is deliberately ignored: nothing here can upload a
  /// session, whatever a caller passes.
  @override
  Future<void> save(String uid, StudyBackup backup) async {
    final data = jsonEncode(backup.settings);
    if (utf8.encode(data).length > 300000) {
      throw StateError('Study settings exceed backup limit');
    }
    final signature = '${backup.modifiedAt}:$data';
    if (_savedSettings[uid] != signature) {
      // Read and write in one transaction: if another phone saved a higher
      // level since this one last read, that level is what stays.
      final doc = _settings(uid);
      final written = await db
          .runTransaction((tx) async {
            final current = await tx.get(doc);
            final merged = _keepFurtherStats(
              backup.settings,
              current.data()?['data'],
            );
            tx.set(doc, {
              'version': 1,
              'ownerUid': uid,
              'data': merged,
              'modifiedAt': backup.modifiedAt,
            });
            return merged;
          })
          .timeout(_wait);
      _savedSettings[uid] = '${backup.modifiedAt}:$written';
    }
    await _deleteLegacySessions(uid);
  }

  /// [settings] encoded for the cloud, with the cloud's stats kept when
  /// [stored], the cloud's current encoded settings, has gone further.
  static String _keepFurtherStats(
    Map<String, dynamic> settings,
    Object? stored,
  ) {
    if (stored is String) {
      try {
        final cloud = jsonDecode(stored);
        if (cloud is Map<String, dynamic>) {
          final mine = settings[StoreKeys.stats];
          final ahead = StudyBackupService._further([
            mine,
            cloud[StoreKeys.stats],
          ]);
          if (ahead != null && !identical(ahead, mine)) {
            return jsonEncode({...settings, StoreKeys.stats: ahead});
          }
        }
      } on FormatException {
        // An unreadable cloud copy has nothing to keep.
      }
    }
    return jsonEncode(settings);
  }

  Future<void> _deleteLegacySessions(String uid) async {
    final pending = _legacySessions[uid];
    if (pending == null) return;
    while (pending.isNotEmpty) {
      final page = pending.take(400).toList(growable: false);
      final batch = db.batch();
      for (final id in page) {
        batch.delete(_sessions(uid).doc(id));
      }
      await batch.commit().timeout(_wait);
      pending.removeAll(page);
    }
  }
}

class StudyBackupService {
  StudyBackupService(this.store, this.backend) {
    _sub = store.changes.listen(_changed);
  }
  final LocalStore store;
  final StudyBackupBackend backend;
  StreamSubscription<String>? _sub;
  Timer? _timer;
  String? _uid;
  bool _restoring = false;
  bool _deferred = false;
  String? _settingsState;
  void Function(UserProfile)? onReconciled;
  int _generation = 0;
  Future<void> _writes = Future.value();

  /// What a linked account keeps in the cloud: the profile, the level and the
  /// leaderboard consent. Earned badges have their own document.
  ///
  /// The consent travels because the public row does: a phone that restored
  /// the row but not the choice would show sharing as off while it was on.
  static const cloudKeys = {
    StoreKeys.user,
    StoreKeys.stats,
    StoreKeys.boardOptIn,
  };

  /// Study setup, kept for each account on this device and never uploaded.
  static const localKeys = {
    StoreKeys.subjects,
    StoreKeys.planLibrary,
    StoreKeys.customPlan,
    StoreKeys.dailyGoal,
    StoreKeys.dailyGoalDays,
    'goal.planner',
  };

  static const keys = {...cloudKeys, ...localKeys};
  String _cache(String uid) => 'study.account.$uid';

  /// Removes study history from every account snapshot kept on this
  /// device, for "Clear local analytics": its sessions, and its stats reset
  /// to [emptyStats]. Without this a cleared history stays in the export
  /// and comes back when that account signs in again.
  static Future<void> forgetHistory(LocalStore store, String emptyStats) async {
    for (final key in store.exportAll().keys) {
      if (!key.startsWith('study.account.')) continue;
      final cached = StudyBackup.fromJson(store.getMap(key));
      if (cached == null) continue;
      await store.setMap(
        key,
        StudyBackup(
          settings: {
            ...cached.settings,
            if (cached.settings.containsKey(StoreKeys.stats))
              StoreKeys.stats: emptyStats,
          },
          sessions: const [],
          modifiedAt: cached.modifiedAt,
        ).toJson(),
      );
    }
  }

  /// The part of [settings] allowed to leave the device.
  ///
  /// Credited session ids are stripped from the stats: each encodes when a
  /// block started, which is exactly the history that stays local. A stats
  /// value that cannot be read is dropped rather than uploaded unfiltered.
  Map<String, dynamic> _cloudSettings(Map<String, dynamic> settings) {
    final cloud = <String, dynamic>{};
    for (final key in cloudKeys) {
      if (!settings.containsKey(key)) continue;
      final value = settings[key];
      if (key != StoreKeys.stats) {
        cloud[key] = value;
        continue;
      }
      final stats = _decodeMap(value);
      if (stats == null) continue;
      cloud[key] = jsonEncode(stats..remove('creditedSessionIds'));
    }
    return cloud;
  }

  static Map<String, dynamic>? _decodeMap(Object? value) {
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// [stats] with this device's credited session ids put back.
  ///
  /// The cloud copy has none, and those receipts are what stop a recovered
  /// block being awarded twice, so restoring a level must not erase them.
  static Object? _withLocalCredits(Object? stats, StudyBackup? local) {
    final restored = _decodeMap(stats);
    if (restored == null) return stats;
    final ids = <String>{
      for (final source in [
        _decodeMap(local?.settings[StoreKeys.stats]),
        restored,
      ])
        if (source?['creditedSessionIds'] case final List credited)
          ...credited.whereType<String>(),
    };
    return jsonEncode({...restored, 'creditedSessionIds': ids.toList()});
  }

  /// Whichever stats value has gone further, by level and then XP, or the
  /// first readable one on a tie.
  ///
  /// Progress only grows, so the further copy is the newest truth wherever
  /// it was earned: a phone that is behind must not upload, or restore, an
  /// older level over it just because it saved something else later.
  static Object? _further(Iterable<Object?> candidates) {
    Object? best;
    (int, int)? bestRank;
    for (final value in candidates) {
      final stats = _decodeMap(value);
      if (stats == null) continue;
      final rank = (
        (stats['level'] as num?)?.toInt() ?? 1,
        (stats['xp'] as num?)?.toInt() ?? 0,
      );
      if (bestRank == null ||
          rank.$1 > bestRank.$1 ||
          (rank.$1 == bestRank.$1 && rank.$2 > bestRank.$2)) {
        best = value;
        bestRank = rank;
      }
    }
    return best;
  }

  String _settingsSignature(String uid) {
    // Only what the cloud holds: a local edit must not outrank a newer profile
    // or level saved from another device.
    final settings = _cloudSettings(_capture(uid).settings);
    final raw = settings[StoreKeys.user];
    if (raw is String) {
      try {
        // Defaults added by a newer app are normalization, not a user edit.
        // Compare the same canonical shape used by profile persistence.
        final user = UserProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        ).toJson();
        user.remove('uid');
        user.remove('isAnonymous');
        settings[StoreKeys.user] = user;
      } catch (_) {}
    }
    return jsonEncode(settings);
  }

  StudyBackup _capture(String uid) {
    final exported = store.exportAll();
    final settings = <String, dynamic>{
      for (final key in keys)
        if (exported.containsKey(key)) key: exported[key],
    };
    final aliases = store.getMap(StoreKeys.achievementAliases) ?? {};
    final owner = store.getString(StoreKeys.achievementHistoryOwner) ?? uid;
    final sessions = <Map<String, dynamic>>[
      for (final row in store.getList(StoreKeys.sessions))
        if (row['ownerUid'] == uid ||
            aliases[row['ownerUid']] == uid ||
            ((row['ownerUid'] == null || row['ownerUid'] == '') &&
                owner == uid))
          {...row, 'ownerUid': uid},
    ];
    return StudyBackup(
      settings: settings,
      sessions: sessions,
      // Older installs have no settings revision. Reading their cache is not
      // a new edit: a fabricated "now" would outrank the saved account and
      // upload stale subjects, goals or sharing consent over that backup.
      modifiedAt: store.getInt('study.modified.$uid') ?? 0,
    );
  }

  void _changed(String key) {
    final uid = _uid;
    if (_restoring ||
        uid == null ||
        (!keys.contains(key) && key != StoreKeys.sessions)) {
      return;
    }
    final profile = store.getMap(StoreKeys.user);
    if (profile?['uid'] != uid || profile?['isAnonymous'] != false) return;
    final signature = _settingsSignature(uid);
    if (signature != _settingsState) {
      _settingsState = signature;
      unawaited(
        store.setInt(
          'study.modified.$uid',
          DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    _timer?.cancel();
    _schedule(uid, const Duration(milliseconds: 500));
  }

  void _schedule(String uid, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush().catchError((Object _) {})));
  }

  /// Continues a credential-backed local session while server reconciliation
  /// runs in the background. No cloud write can precede that successful read.
  void resumeLocal(UserProfile profile) {
    final stored = store.getMap(StoreKeys.user);
    if (profile.isAnonymous ||
        stored?['uid'] != profile.uid ||
        stored?['isAnonymous'] != false) {
      return;
    }
    _generation++;
    _uid = profile.uid;
    _deferred = true;
    _settingsState = _settingsSignature(profile.uid);
    _schedule(profile.uid, const Duration(milliseconds: 500));
  }

  /// Called before publishing an authenticated profile. Identity switches are
  /// cached separately; a registered account's history never becomes a guest gift.
  Future<UserProfile> connect(
    UserProfile profile, {
    bool reconcile = false,
  }) async {
    if (profile.isAnonymous) return profile;
    if (_uid == profile.uid && !reconcile) {
      return profile;
    }
    final generation = ++_generation;
    void checkCurrent() {
      if (generation != _generation) {
        throw StateError('Account changed during restore');
      }
    }

    _timer?.cancel();
    _uid = reconcile ? profile.uid : null;
    final old = store.getMap(StoreKeys.user);
    final oldUid = old?['uid'] as String? ?? '';
    final firstLink =
        oldUid.isNotEmpty &&
        oldUid != profile.uid &&
        old?['isAnonymous'] == true &&
        store.getBool('achievements.linked.$oldUid') == false;
    if (oldUid.isNotEmpty) {
      await store.setMap(_cache(oldUid), _capture(oldUid).toJson());
      checkCurrent();
    }
    var local = oldUid == profile.uid
        ? _capture(profile.uid)
        : StudyBackup.fromJson(store.getMap(_cache(profile.uid)));
    // Unknown server state is never an empty account. A failed read must not
    // permit guest or stale cached settings to overwrite a returning account.
    StudyBackup? remote;
    try {
      remote = await backend.load(profile.uid);
    } catch (_) {
      if (generation != _generation) rethrow;
      // A known identity can keep studying from its own device snapshot.
      // Keep cloud writes fenced until server reconciliation succeeds.
      if (!reconcile &&
          oldUid == profile.uid &&
          local != null &&
          store.getBool('achievements.linked.${profile.uid}') == true) {
        _uid = profile.uid;
        _deferred = true;
        _settingsState = _settingsSignature(profile.uid);
        _schedule(profile.uid, const Duration(seconds: 20));
        return profile;
      }
      rethrow;
    }
    if (generation != _generation) {
      throw StateError('Account changed during restore');
    }
    if (oldUid == profile.uid &&
        store.getMap(StoreKeys.user)?['uid'] == profile.uid) {
      // Background reconciliation can overlap a completed local session or
      // goal edit. Merge the latest device snapshot after the network wait.
      local = _capture(profile.uid);
    }
    final guest = firstLink ? _capture(oldUid) : null;
    // A first upload can write session batches before its settings document.
    // Missing or corrupt settings have no revision to compete with local data.
    final remoteSettings = remote?.hasSettings == true ? remote : null;
    final base =
        local != null &&
            (remoteSettings == null ||
                local.modifiedAt > remoteSettings.modifiedAt)
        ? local
        : remoteSettings;
    final chosen = base ?? guest;
    final merged = <String, Map<String, dynamic>>{};
    for (final backup in [remote, local, guest]) {
      for (final row in backup?.sessions ?? <Map<String, dynamic>>[]) {
        final id = row['id'];
        if (id is String) merged[id] = {...row, 'ownerUid': profile.uid};
      }
    }
    final settings = chosen?.settings ?? <String, dynamic>{};
    // Local setup comes from the winning snapshot when it has any: that is the
    // device itself, or a document an older build wrote, read this once before
    // the next save strips it. A current cloud document has none, so the
    // account's own copy on this device stands.
    Object? restoredValue(String key) {
      if (settings.containsKey(key)) return settings[key];
      if (!localKeys.contains(key)) return null;
      for (final source in [local, remoteSettings, guest]) {
        if (source?.settings.containsKey(key) == true) {
          return source!.settings[key];
        }
      }
      return null;
    }

    UserProfile restored = profile;
    final raw = settings[StoreKeys.user];
    if (raw is String) {
      try {
        restored = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>)
            .copyWith(uid: profile.uid, isAnonymous: false);
      } catch (_) {}
    }
    // A different registered account starts with its own choices only.
    if (chosen == null && oldUid.isNotEmpty && oldUid != profile.uid) {
      restored = UserProfile(
        uid: profile.uid,
        displayName: profile.displayName,
        isAnonymous: false,
        createdAt: profile.createdAt,
      );
    }
    _restoring = true;
    _uid = null;
    try {
      for (final key in keys) {
        checkCurrent();
        if (key == StoreKeys.user) continue;
        final value = key == StoreKeys.stats
            ? _withLocalCredits(
                _further([
                  restoredValue(key),
                  local?.settings[key],
                  remoteSettings?.settings[key],
                ]),
                local,
              )
            : restoredValue(key);
        if (value is String) {
          await store.setString(key, value);
        } else if (value is bool) {
          await store.setBool(key, value);
        } else if (value is int) {
          await store.setInt(key, value);
        } else {
          await store.remove(key);
        }
      }
      checkCurrent();
      await store.setList(
        StoreKeys.sessions,
        merged.values.toList()..sort(
          (a, b) => (a['startedAt'] as int? ?? 0).compareTo(
            b['startedAt'] as int? ?? 0,
          ),
        ),
      );
      checkCurrent();
      if (oldUid.isNotEmpty && oldUid != profile.uid) {
        final pending = store.getMap(StoreKeys.presets);
        await store.setMap(StoreKeys.presets, {
          if (pending?['pendingCompletions'] is List)
            'pendingCompletions': pending!['pendingCompletions'],
          if (pending?['pendingStats'] is List)
            'pendingStats': pending!['pendingStats'],
        });
        checkCurrent();
      }
      await store.setMap(StoreKeys.user, restored.toJson());
      checkCurrent();
      await store.setBool(
        'leaderboard.consent.${profile.uid}',
        store.getBool(StoreKeys.boardOptIn) ?? false,
      );
      checkCurrent();
      await store.setString(StoreKeys.achievementHistoryOwner, profile.uid);
      checkCurrent();
      await store.setBool('achievements.linked.${profile.uid}', true);
      checkCurrent();
      await store.setInt(
        'study.modified.${profile.uid}',
        chosen?.modifiedAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (generation != _generation) {
        throw StateError('Account changed during restore');
      }
      _uid = profile.uid;
      _deferred = false;
      _settingsState = _settingsSignature(profile.uid);
      await store.setMap(_cache(profile.uid), _capture(profile.uid).toJson());
      checkCurrent();
    } finally {
      _restoring = false;
    }
    checkCurrent();
    if (!reconcile) _schedule(profile.uid, const Duration(milliseconds: 500));
    return restored;
  }

  Future<void> flush() {
    _timer?.cancel();
    final uid = _uid;
    if (uid == null || _restoring) return Future.value();
    final generation = _generation;
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (generation != _generation || _uid != uid) return;
      try {
        var backup = _capture(uid);
        await store.setMap(_cache(uid), backup.toJson());
        if (generation != _generation || _uid != uid) return;
        if (_deferred) {
          final raw = store.getMap(StoreKeys.user);
          if (raw == null || raw['uid'] != uid) return;
          final restored = await connect(
            UserProfile.fromJson(raw),
            reconcile: true,
          );
          if (_uid != uid) return;
          onReconciled?.call(restored);
          backup = _capture(uid);
        } else {
          // Another phone may have saved a higher level since this one last
          // read the cloud. Keep it, here and in what is uploaded.
          final remote = await backend.load(uid);
          if (generation != _generation || _uid != uid) return;
          // A session may have finished during the read: compare against
          // this phone's progress as it is now.
          backup = _capture(uid);
          final mine = backup.settings[StoreKeys.stats];
          final ahead = _further([mine, remote?.settings[StoreKeys.stats]]);
          if (ahead != null && !identical(ahead, mine)) {
            _restoring = true;
            try {
              await store.setString(
                StoreKeys.stats,
                _withLocalCredits(ahead, backup) as String,
              );
            } finally {
              _restoring = false;
            }
            if (generation != _generation || _uid != uid) return;
            _settingsState = _settingsSignature(uid);
            backup = _capture(uid);
            final raw = store.getMap(StoreKeys.user);
            if (raw != null && raw['uid'] == uid) {
              onReconciled?.call(UserProfile.fromJson(raw));
            }
          }
        }
        await backend.save(
          uid,
          StudyBackup(
            settings: _cloudSettings(backup.settings),
            sessions: const [],
            modifiedAt: backup.modifiedAt,
          ),
        );
      } catch (_) {
        // Reconciliation increments the generation. Retry only while this
        // account remains current, even if the network read failed.
        if (_uid == uid ||
            (_uid == null &&
                _deferred &&
                store.getMap(StoreKeys.user)?['uid'] == uid)) {
          _uid = uid;
          _schedule(uid, const Duration(seconds: 20));
        }
        rethrow;
      }
    });
    _writes = next;
    return next;
  }

  /// Cache unsynced local data without waiting behind deferred server reads.
  /// A normal connected session still gets its best-effort final upload.
  Future<void> prepareSignOut() async {
    if (!_deferred) return flush();
    final uid = _uid;
    disconnect();
    if (uid != null && store.getMap(StoreKeys.user)?['uid'] == uid) {
      await store.setMap(_cache(uid), _capture(uid).toJson());
    }
  }

  void disconnect() {
    _generation++;
    _uid = null;
    _deferred = false;
    _timer?.cancel();
    _writes = Future.value();
  }

  void dispose() {
    disconnect();
    unawaited(_sub?.cancel());
  }
}

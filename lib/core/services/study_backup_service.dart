import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import 'local_store.dart';

/// Private study data, independent of optional public leaderboard sharing.
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
  final _saved = <String, String>{};
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
          _saved['$uid/${doc.id}'] = jsonEncode(row);
        }
      }
      if (page.docs.length < 400) break;
      last = page.docs.last;
    }
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

  @override
  Future<void> save(String uid, StudyBackup backup) async {
    final data = jsonEncode(backup.settings);
    if (utf8.encode(data).length > 300000) {
      throw StateError('Study settings exceed backup limit');
    }
    final pending = <MapEntry<String, Map<String, dynamic>>>[];
    for (final row in backup.sessions) {
      final id = row['id'];
      if (id is! String || row['ownerUid'] != uid) continue;
      final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
      if (_saved['$uid/$encoded'] != jsonEncode(row)) {
        pending.add(MapEntry(encoded, row));
      }
    }
    for (var start = 0; start < pending.length; start += 400) {
      final batch = db.batch();
      for (final entry in pending.skip(start).take(400)) {
        batch.set(_sessions(uid).doc(entry.key), entry.value);
      }
      await batch.commit().timeout(_wait);
      for (final entry in pending.skip(start).take(400)) {
        _saved['$uid/${entry.key}'] = jsonEncode(entry.value);
      }
    }
    await _settings(uid)
        .set({
          'version': 1,
          'ownerUid': uid,
          'data': data,
          'modifiedAt': backup.modifiedAt,
        })
        .timeout(_wait);
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
  static const keys = {
    StoreKeys.user,
    StoreKeys.subjects,
    StoreKeys.planLibrary,
    StoreKeys.customPlan,
    StoreKeys.dailyGoal,
    StoreKeys.dailyGoalDays,
    'goal.planner',
    StoreKeys.stats,
    StoreKeys.boardOptIn,
  };
  String _cache(String uid) => 'study.account.$uid';
  String _settingsSignature(String uid) {
    final settings = {..._capture(uid).settings};
    final raw = settings[StoreKeys.user];
    if (raw is String) {
      try {
        final user = Map<String, dynamic>.from(jsonDecode(raw) as Map);
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
        final value = settings[key];
        if (key == StoreKeys.user) continue;
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
        }
        await backend.save(uid, backup);
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

  void disconnect() {
    _generation++;
    _uid = null;
    _deferred = false;
    _timer?.cancel();
  }

  void dispose() {
    disconnect();
    unawaited(_sub?.cancel());
  }
}

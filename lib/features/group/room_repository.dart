import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'group_models.dart';

class RoomException implements Exception {
  RoomException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Realtime group challenge rooms on Firestore (`rooms/{code}` and
/// `rooms/{code}/players/{uid}`), protected by security rules.
class RoomRepository {
  RoomRepository([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final _rng = math.Random.secure();

  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw RoomException('You are offline. Connect to the internet to play together.');
    return u.uid;
  }

  DocumentReference<Map<String, dynamic>> _room(String code) => _db.collection('rooms').doc(code);
  CollectionReference<Map<String, dynamic>> _players(String code) => _room(code).collection('players');

  String _newCode() => List.generate(6, (_) => kRoomAlphabet[_rng.nextInt(kRoomAlphabet.length)]).join();

  static String normalise(String code) => code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  static String joinUrl(String code, {String? origin}) {
    final base = origin ?? (kIsWeb ? Uri.base.origin : 'https://rockketeyes.web.app');
    return '$base/join/$code';
  }

  Future<String> createRoom({required RoomConfig config, required String hostName}) async {
    final uid = _uid;
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _newCode();
      final ref = _room(code);
      final created = await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return false;
        tx.set(ref, {
          'hostUid': uid,
          'hostName': hostName,
          'status': RoomStatus.lobby.name,
          'config': config.toJson(),
          'seed': _rng.nextInt(0x7FFFFFFF),
          'round': 0,
          'startAtMs': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) return code;
    }
    throw RoomException('Could not create a room. Please try again.');
  }

  Stream<Room?> watchRoom(String code) => _room(code)
      .snapshots()
      .map((s) => s.exists ? Room.fromDoc(code, s.data()!) : null);

  Stream<List<RoomPlayer>> watchPlayers(String code) => _players(code).snapshots().map(
      (q) => q.docs.map((d) => RoomPlayer.fromDoc(d.data())).toList()..sort((a, b) => a.joinedAtMs.compareTo(b.joinedAtMs)));

  Future<Room?> getRoom(String code) async {
    final s = await _room(code).get();
    return s.exists ? Room.fromDoc(code, s.data()!) : null;
  }

  Future<void> join(String code, {required String nickname, required String avatar}) async {
    final uid = _uid;
    final room = await getRoom(code);
    if (room == null) throw RoomException('No game found with PIN $code.');
    final existing = await _players(code).doc(uid).get();
    final data = {
      'uid': uid,
      'nickname': nickname,
      'avatar': avatar,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (existing.exists) {
      await _players(code).doc(uid).update(data);
      return;
    }
    if (room.status != RoomStatus.lobby) {
      throw RoomException('This game has already started. Ask the host to start a new round.');
    }
    await _players(code).doc(uid).set({
      ...data,
      'joinedAt': FieldValue.serverTimestamp(),
      'joinedAtMs': DateTime.now().millisecondsSinceEpoch,
      'round': room.round,
      'state': PlayerState.waiting.name,
      'correct': 0,
      'cells': room.config.size.cells,
      'score': 0,
      'elapsedMs': 0,
      'finishedAt': null,
    });
  }

  Future<void> leave(String code) async {
    try {
      await _players(code).doc(_uid).delete();
    } catch (_) {}
  }

  Future<void> reportProgress(String code, {required int round, required int correct, required int cells, required int elapsedMs}) =>
      _players(code).doc(_uid).update({
        'round': round,
        'state': PlayerState.playing.name,
        'correct': correct,
        'cells': cells,
        'elapsedMs': elapsedMs,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> reportFinish(String code,
          {required int round,
          required bool cleared,
          required int correct,
          required int cells,
          required int score,
          required int elapsedMs}) =>
      _players(code).doc(_uid).update({
        'round': round,
        'state': cleared ? PlayerState.cleared.name : PlayerState.out.name,
        'correct': correct,
        'cells': cells,
        'score': score,
        'elapsedMs': elapsedMs,
        'finishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---- Host controls ----

  Future<void> updateConfig(String code, RoomConfig config) =>
      _room(code).update({'config': config.toJson(), 'updatedAt': FieldValue.serverTimestamp()});

  /// Starts a new round: fresh seed, every player reset, synchronized countdown.
  Future<void> startRound(Room room, List<RoomPlayer> players) async {
    final round = room.round + 1;
    final batch = _db.batch();
    for (final p in players) {
      if (p.state == PlayerState.left) continue;
      batch.update(_players(room.code).doc(p.uid), {
        'round': round,
        'state': PlayerState.waiting.name,
        'correct': 0,
        'cells': room.config.size.cells,
        'score': 0,
        'elapsedMs': 0,
        'finishedAt': null,
      });
    }
    batch.update(_room(room.code), {
      'status': RoomStatus.countdown.name,
      'seed': _rng.nextInt(0x7FFFFFFF),
      'round': round,
      'startAtMs': DateTime.now().millisecondsSinceEpoch + 3800,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> setStatus(String code, RoomStatus status) =>
      _room(code).update({'status': status.name, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> backToLobby(Room room, List<RoomPlayer> players) async {
    final batch = _db.batch();
    for (final p in players) {
      batch.update(_players(room.code).doc(p.uid), {'state': PlayerState.waiting.name, 'correct': 0, 'score': 0, 'elapsedMs': 0});
    }
    batch.update(_room(room.code), {'status': RoomStatus.lobby.name, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> kick(String code, String uid) => _players(code).doc(uid).delete();

  Future<void> closeRoom(String code) async {
    final players = await _players(code).get();
    final batch = _db.batch();
    for (final d in players.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_room(code));
    await batch.commit();
  }
}

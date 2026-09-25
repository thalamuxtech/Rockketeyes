import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'local_store.dart';

class Profile {
  const Profile({
    required this.uid,
    required this.nickname,
    required this.avatarSeed,
    required this.country,
    this.registered = false,
    this.linked = false,
    this.gamesPlayed = 0,
  });

  final String uid;
  final String nickname;
  final String avatarSeed;
  final String country;

  /// True once the nickname has been saved on the server.
  final bool registered;

  /// True when the anonymous account is linked to Google.
  final bool linked;
  final int gamesPlayed;

  Profile copyWith({String? nickname, String? avatarSeed, String? country, bool? registered, bool? linked}) =>
      Profile(
        uid: uid,
        nickname: nickname ?? this.nickname,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        country: country ?? this.country,
        registered: registered ?? this.registered,
        linked: linked ?? this.linked,
        gamesPlayed: gamesPlayed,
      );
}

/// Anonymous-first identity with an optional Google upgrade.
class ProfileController extends AsyncNotifier<Profile> {
  LocalStore get _store => LocalStore.instance;

  @override
  Future<Profile> build() async {
    final user = await _ensureUser();
    final uid = user?.uid ?? 'offline';
    final local = Profile(
      uid: uid,
      nickname: _store.get<String>('nickname') ?? '',
      avatarSeed: _store.get<String>('avatarSeed') ?? uid,
      country: _store.get<String>('country') ?? _deviceCountry(),
      registered: _store.get<bool>('registered') ?? false,
      linked: _isLinked(user),
    );
    if (user == null) return local;
    unawaited(_refreshFromServer(local));
    return local;
  }

  static bool _isLinked(User? u) =>
      u != null && u.providerData.any((p) => p.providerId == 'google.com');

  static String _deviceCountry() {
    final code = PlatformDispatcher.instance.locale.countryCode ?? '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : '';
  }

  Future<User?> _ensureUser() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    try {
      final cred = await auth.signInAnonymously().timeout(const Duration(seconds: 10));
      return cred.user;
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
      return null;
    }
  }

  Future<void> _refreshFromServer(Profile local) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(local.uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final d = snap.data();
      if (d == null) return;
      final remote = Profile(
        uid: local.uid,
        nickname: (d['nickname'] as String?) ?? local.nickname,
        avatarSeed: (d['avatarSeed'] as String?) ?? local.avatarSeed,
        country: (d['country'] as String?) ?? local.country,
        registered: d['nicknameLower'] != null,
        linked: local.linked,
        gamesPlayed: (d['gamesPlayed'] as num?)?.toInt() ?? 0,
      );
      await _cache(remote);
      state = AsyncData(remote);
    } catch (e) {
      debugPrint('Profile refresh failed: $e');
    }
  }

  Future<void> _cache(Profile p) async {
    await _store.set('nickname', p.nickname);
    await _store.set('avatarSeed', p.avatarSeed);
    await _store.set('country', p.country);
    await _store.set('registered', p.registered);
  }

  /// Saves nickname/avatar/country. Throws [ApiException] on validation errors.
  Future<void> save({required String nickname, required String avatarSeed, required String country}) async {
    final current = state.value ?? await future;
    await _ensureUser();
    final res = await ApiClient.instance.post('/profile', {
      'nickname': nickname,
      'avatarSeed': avatarSeed,
      'country': country,
    });
    final p = (res['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final next = current.copyWith(
      nickname: (p['nickname'] as String?) ?? nickname,
      avatarSeed: (p['avatarSeed'] as String?) ?? avatarSeed,
      country: (p['country'] as String?) ?? country,
      registered: true,
    );
    await _cache(next);
    state = AsyncData(next);
  }

  /// Keeps the same uid (and scores) while adding a Google login.
  Future<void> linkGoogle() async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) return;
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await user.linkWithPopup(provider);
    } else {
      await user.linkWithProvider(provider);
    }
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(linked: true));
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, Profile>(ProfileController.new);

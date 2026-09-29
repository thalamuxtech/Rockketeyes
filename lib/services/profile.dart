import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/avatar/avatar_spec.dart';
import '../core/env.dart';
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
    this.email,
    this.gamesPlayed = 0,
  });

  final String uid;
  final String nickname;

  /// Encoded avatar (see [AvatarSpec]).
  final String avatarSeed;
  final String country;

  /// True once the nickname has been saved on the server.
  final bool registered;

  /// True when a Google account is connected. Required for Global Legends.
  final bool linked;
  final String? email;
  final int gamesPlayed;

  Profile copyWith({
    String? nickname,
    String? avatarSeed,
    String? country,
    bool? registered,
    bool? linked,
    String? email,
  }) =>
      Profile(
        uid: uid,
        nickname: nickname ?? this.nickname,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        country: country ?? this.country,
        registered: registered ?? this.registered,
        linked: linked ?? this.linked,
        email: email ?? this.email,
        gamesPlayed: gamesPlayed,
      );
}

/// Result of connecting Google.
class GoogleConnectResult {
  const GoogleConnectResult({required this.switchedAccount, required this.claimed});

  /// The Google account already had a Rockketeyes profile, so we signed into
  /// it (this device's guest progress stays local).
  final bool switchedAccount;

  /// Number of past best scores added to Global Legends.
  final int claimed;
}

/// Anonymous-first identity with a Google upgrade for Global Legends.
class ProfileController extends AsyncNotifier<Profile> {
  LocalStore get _store => LocalStore.instance;

  @override
  Future<Profile> build() async {
    final user = await _ensureUser();
    final uid = user?.uid ?? 'offline';
    final local = Profile(
      uid: uid,
      nickname: _store.get<String>('nickname') ?? '',
      avatarSeed: _store.get<String>('avatarSeed') ?? DicebearAvatar('adventurer', uid.substring(0, uid.length.clamp(0, 10))).encode(),
      country: _store.get<String>('country') ?? _deviceCountry(),
      registered: _store.get<bool>('registered') ?? false,
      linked: _isLinked(user),
      email: _googleEmail(user),
    );
    if (user == null) return local;
    unawaited(_refreshFromServer(local));
    return local;
  }

  static bool _isLinked(User? u) => u != null && u.providerData.any((p) => p.providerId == 'google.com');

  static String? _googleEmail(User? u) {
    if (u == null) return null;
    for (final p in u.providerData) {
      if (p.providerId == 'google.com') return p.email ?? u.email;
    }
    return null;
  }

  static String _deviceCountry() {
    final code = PlatformDispatcher.instance.locale.countryCode ?? '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : '';
  }

  Future<User?> _ensureUser() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    try {
      final cred = await auth.signInAnonymously().timeout(const Duration(seconds: 30));
      return cred.user;
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
      return null;
    }
  }

  Future<void> _refreshFromServer(Profile local) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(local.uid).get().timeout(const Duration(seconds: 8));
      final d = snap.data();
      if (d == null) return;
      final remote = Profile(
        uid: local.uid,
        nickname: (d['nickname'] as String?) ?? local.nickname,
        avatarSeed: (d['avatarSeed'] as String?) ?? local.avatarSeed,
        country: (d['country'] as String?) ?? local.country,
        registered: d['nicknameLower'] != null,
        linked: local.linked,
        email: local.email,
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
    }, retry: true);
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

  /// Keeps the local look even before the server has it (e.g. offline).
  Future<void> setLocalAvatar(String avatarSeed) async {
    final current = state.value;
    if (current == null) return;
    final next = current.copyWith(avatarSeed: avatarSeed);
    await _cache(next);
    state = AsyncData(next);
  }

  /// Connects Google to this player. If that Google account already owns a
  /// Rockketeyes profile, signs into it instead so progress is restored.
  /// Afterwards, past best scores are added to Global Legends.
  Future<GoogleConnectResult> connectGoogle() async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? await _ensureUser();
    if (user == null) throw FirebaseAuthException(code: 'network-request-failed', message: 'Offline');
    var switched = false;
    AuthCredential? nativeCred;
    try {
      if (Env.useEmulator && Env.e2e) {
        await user.linkWithCredential(_emulatorGoogleCredential());
      } else if (kIsWeb) {
        await user.linkWithPopup(GoogleAuthProvider());
      } else {
        // Native account picker: no browser hand-off, so no lost state.
        nativeCred = await _nativeGoogleCredential();
        await user.linkWithCredential(nativeCred);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        final cred = e.credential ?? nativeCred;
        if (cred != null) {
          await auth.signInWithCredential(cred);
        } else if (kIsWeb) {
          await auth.signInWithPopup(GoogleAuthProvider());
        } else {
          await auth.signInWithProvider(GoogleAuthProvider());
        }
        switched = true;
        await _store.set('registered', false);
      } else {
        rethrow;
      }
    }
    await auth.currentUser?.getIdToken(true);
    var claimed = 0;
    try {
      final res = await ApiClient.instance.post('/legends/claim', {}, retry: true);
      claimed = (res['claimed'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('claim failed: $e');
    }
    ref.invalidateSelf();
    await future;
    return GoogleConnectResult(switchedAccount: switched, claimed: claimed);
  }

  static bool _googleReady = false;

  /// Google ID token from the Android account picker (Credential Manager).
  static Future<AuthCredential> _nativeGoogleCredential() async {
    final gs = GoogleSignIn.instance;
    if (!_googleReady) {
      await gs.initialize(serverClientId: Env.googleServerClientId);
      _googleReady = true;
    }
    final account = await gs.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token', message: 'Google did not return an ID token.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Auth emulator accepts unsigned Google ID tokens (E2E tests only).
  static int _fakeGoogleCounter = 0;
  static AuthCredential _emulatorGoogleCredential() {
    final id = '${DateTime.now().millisecondsSinceEpoch}${_fakeGoogleCounter++}';
    return GoogleAuthProvider.credential(
      idToken: '{"sub":"e2e-$id","email":"pilot$id@example.com","email_verified":true,"name":"E2E Pilot"}',
    );
  }

  Future<void> signOut() async {
    if (!kIsWeb && _googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
    await _store.set('registered', false);
    await _store.set('nickname', '');
    ref.invalidateSelf();
  }

  /// Permanently deletes the player's account, scores and leaderboard rows on
  /// the server, then forgets them on this device. A fresh anonymous player
  /// is created afterwards. Throws [ApiException] if the server refuses.
  Future<void> deleteAccount() async {
    if (FirebaseAuth.instance.currentUser != null) {
      await ApiClient.instance.post('/account/delete', {}, retry: true);
    }
    if (!kIsWeb && _googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
    await _store.clearPlayer();
    ref.invalidateSelf();
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, Profile>(ProfileController.new);

// Firebase configuration for project `rockketeyes`.
// These identifiers are public by design; access is enforced by Firestore
// security rules, server-side validation and App Check.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Rockketeyes supports Android and web only.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCIQ6_V7-I8DGyPmcsQzlTqUuQlDCcJqLU',
    appId: '1:685148954018:web:72223f0278964fee8ee6fb',
    messagingSenderId: '685148954018',
    projectId: 'rockketeyes',
    authDomain: 'rockketeyes.firebaseapp.com',
    storageBucket: 'rockketeyes.firebasestorage.app',
    measurementId: 'G-5Z5HHN3PVK',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCa40atiqCQskGaztLVy49hW1mYQhqki84',
    appId: '1:685148954018:android:3d7a2da208c754398ee6fb',
    messagingSenderId: '685148954018',
    projectId: 'rockketeyes',
    storageBucket: 'rockketeyes.firebasestorage.app',
  );
}

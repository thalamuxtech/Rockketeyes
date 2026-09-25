import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/env.dart';
import 'firebase_options.dart';
import 'services/api_client.dart';
import 'services/audio_service.dart';
import 'services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF07060F),
  ));

  await LocalStore.init();
  await _initFirebase();
  unawaited(AudioService.instance.init());

  runApp(const ProviderScope(child: RocketEyeApp()));
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (Env.useEmulator) {
      final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && Env.emulatorHost == '127.0.0.1')
          ? '10.0.2.2'
          : Env.emulatorHost;
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    } else {
      final webKey = Env.appCheckWebKey;
      if (!kIsWeb || webKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
          providerWeb: webKey.isEmpty ? null : ReCaptchaEnterpriseProvider(webKey),
        );
        ApiClient.appCheckEnabled = true;
      }
    }
  } catch (e) {
    debugPrint('Firebase init failed (offline practice only): $e');
  }
}

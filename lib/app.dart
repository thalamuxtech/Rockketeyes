import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/e2e/e2e_hooks.dart';
import 'core/env.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'services/audio_service.dart';
import 'services/settings.dart';

class RocketEyeApp extends ConsumerStatefulWidget {
  const RocketEyeApp({super.key});

  @override
  ConsumerState<RocketEyeApp> createState() => _RocketEyeAppState();
}

class _RocketEyeAppState extends ConsumerState<RocketEyeApp> {
  late final GoRouter _router = buildRouter();

  @override
  void initState() {
    super.initState();
    if (Env.e2e) installE2EHooks(_router);
  }

  @override
  Widget build(BuildContext context) {
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    return MaterialApp.router(
      title: 'RocketEye',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final disable = switch (motion) {
          MotionPref.system => mq.disableAnimations,
          MotionPref.reduced => true,
          MotionPref.full => false,
        };
        // Browsers need a gesture before audio can start.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => AudioService.instance.unlock(),
          child: MediaQuery(
            data: mq.copyWith(
              disableAnimations: disable,
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          ),
        );
      },
    );
  }
}

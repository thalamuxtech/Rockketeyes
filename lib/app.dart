import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/e2e/e2e_hooks.dart';
import 'core/env.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'services/audio_service.dart';
import 'services/profile.dart';

class RockketeyesApp extends ConsumerStatefulWidget {
  const RockketeyesApp({super.key});

  @override
  ConsumerState<RockketeyesApp> createState() => _RockketeyesAppState();
}

class _RockketeyesAppState extends ConsumerState<RockketeyesApp> {
  late final GoRouter _router = buildRouter();
  SemanticsHandle? _semantics;

  @override
  void dispose() {
    _semantics?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (Env.e2e) {
      // Keep the accessibility tree on so tests can find controls by label.
      _semantics = SemanticsBinding.instance.ensureSemantics();
      installE2EHooks(_router, connectGoogle: () => ref.read(profileProvider.notifier).connectGoogle());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Rockketeyes',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Browsers need a gesture before audio can start.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => AudioService.instance.unlock(),
          child: MediaQuery(
            data: mq.copyWith(
              disableAnimations: false, // Rockketeyes always plays its full animations.
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          ),
        );
      },
    );
  }
}

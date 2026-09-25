import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/game/application/game_config.dart';
import '../features/game/presentation/game_screen.dart';
import '../features/home/home_screen.dart';
import '../features/legends/legends_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../services/local_store.dart';
import 'theme/app_theme.dart';

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.medium,
      reverseTransitionDuration: AppMotion.short,
      transitionsBuilder: (context, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: AppMotion.curve),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: AppMotion.curve)),
          child: child,
        ),
      ),
    );

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final onboarded = LocalStore.instance.get<bool>('onboarded') ?? false;
        if (!onboarded && state.matchedLocation == '/') return '/onboarding';
        return null;
      },
      routes: [
        GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const HomeScreen())),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (c, s) => _fade(s, OnboardingScreen(replay: s.uri.queryParameters['replay'] == '1')),
        ),
        GoRoute(
          path: '/play',
          pageBuilder: (c, s) {
            final config = s.extra is GameConfig
                ? s.extra! as GameConfig
                : GameConfig.fromJson(LocalStore.instance.get<Map<dynamic, dynamic>>('lastConfig'));
            return _fade(s, GameScreen(key: ValueKey(config.boardId), config: config));
          },
        ),
        GoRoute(
          path: '/legends',
          pageBuilder: (c, s) => _fade(s, LegendsScreen(initialBoard: s.uri.queryParameters['board'])),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (c, s) => _fade(s, ProfileScreen(welcome: s.uri.queryParameters['welcome'] == '1')),
        ),
        GoRoute(path: '/settings', pageBuilder: (c, s) => _fade(s, const SettingsScreen())),
      ],
    );

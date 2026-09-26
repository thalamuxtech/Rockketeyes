import 'package:go_router/go_router.dart';

import 'e2e_hooks_stub.dart' if (dart.library.js_interop) 'e2e_hooks_web.dart' as impl;

/// Exposes `window.reE2E` for the Playwright suite (only with RE_E2E=true).
void installE2EHooks(GoRouter router, {required Future<Object?> Function() connectGoogle}) =>
    impl.install(router, connectGoogle: connectGoogle);

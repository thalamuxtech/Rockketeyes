import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact floating toast, centred and width-capped on large screens.
void showToast(BuildContext context, String message, {IconData? icon}) {
  final width = MediaQuery.sizeOf(context).width;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    width: width > 520 ? 440 : null,
    margin: width > 520 ? null : const EdgeInsets.fromLTRB(16, 0, 16, 16),
    duration: const Duration(seconds: 3),
    content: Row(
      children: [
        Icon(icon ?? Icons.check_circle_rounded, size: 18, color: AppColors.gold),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: AppText.body(14))),
      ],
    ),
  ));
}

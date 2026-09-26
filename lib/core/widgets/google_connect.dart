import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/profile.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'toast.dart';

/// Runs the Google connect flow with friendly feedback. Returns true on success.
Future<bool> connectGoogleFlow(BuildContext context, WidgetRef ref) async {
  try {
    final r = await ref.read(profileProvider.notifier).connectGoogle();
    if (!context.mounted) return true;
    showToast(
      context,
      r.switchedAccount
          ? 'Welcome back! Your saved Rockketeyes profile is restored.'
          : r.claimed > 0
              ? 'Google connected. ${r.claimed} best score${r.claimed == 1 ? '' : 's'} added to Global Legends.'
              : 'Google connected. You are on Global Legends now.',
    );
    return true;
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return false;
    final msg = switch (e.code) {
      'popup-closed-by-user' || 'cancelled-popup-request' || 'web-context-canceled' => null,
      'popup-blocked' => 'Your browser blocked the Google window. Allow pop-ups and try again.',
      'operation-not-allowed' => 'Google sign-in is not enabled for this app yet.',
      'network-request-failed' => 'No connection. Try again when you are online.',
      _ => 'Could not connect Google (${e.code}).',
    };
    if (msg != null) showToast(context, msg, icon: Icons.error_outline_rounded);
    return false;
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not connect Google.', icon: Icons.error_outline_rounded);
    return false;
  }
}

/// Google "G" mark drawn with the four brand colors.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    final c = Offset(r, r);
    final w = s.width * 0.2;
    final rect = Rect.fromCircle(center: c, radius: r - w / 2);
    Paint p(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    const d = 3.14159265 / 180;
    canvas.drawArc(rect, -40 * d, -95 * d, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -135 * d, -90 * d, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 135 * d, -90 * d, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 45 * d, -45 * d, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(c, Offset(s.width - w / 4, r), p(const Color(0xFF4285F4)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// White "Continue with Google" button.
class GoogleButton extends StatefulWidget {
  const GoogleButton({super.key, required this.onPressed, this.label = 'Connect Google'});

  final Future<void> Function() onPressed;
  final String label;

  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.onPressed();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                else
                  const GoogleMark(),
                const SizedBox(width: 10),
                Text(widget.label, style: AppText.label(15, color: const Color(0xFF1F1F1F))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains why to connect Google and offers the button (or shows status).
class GoogleConnectCard extends ConsumerWidget {
  const GoogleConnectCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return const SizedBox.shrink();
    if (profile.linked) {
      return GlassPanel(
        borderColor: AppColors.success.withValues(alpha: 0.4),
        child: Row(
          children: [
            const Icon(LucideIcons.badgeCheck, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Google connected', style: AppText.label(15)),
                  Text(
                    '${profile.email ?? 'Your account'} · progress saved, on Global Legends',
                    style: AppText.body(12, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GlassPanel(
      glow: AppColors.gold.withValues(alpha: 0.12),
      borderColor: AppColors.gold.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(LucideIcons.trophy, color: AppColors.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('Join Global Legends', style: AppText.heading(17))),
          ]),
          const SizedBox(height: 6),
          Text(
            compact
                ? 'Connect Google to save your progress and rank worldwide.'
                : 'Connect your Google account to save your progress on any device and put your '
                    'scores on the worldwide leaderboards. Your best scores so far are added automatically.',
            style: AppText.body(13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          GoogleButton(onPressed: () => connectGoogleFlow(context, ref)),
        ],
      ),
    );
  }
}

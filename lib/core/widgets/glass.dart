import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/audio_service.dart';
import '../theme/app_theme.dart';

/// Frosted-glass surface.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius = AppRadius.md,
    this.blur = 18,
    this.fill = AppColors.glassFill,
    this.borderColor = AppColors.glassBorder,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color fill;
  final Color borderColor;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          if (glow != null) BoxShadow(color: glow!, blurRadius: 32, spreadRadius: -6),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: r,
              border: Border.all(color: borderColor),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Primary call to action: gold gradient pill with a soft glow.
class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.height = 58,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;
  final bool busy;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    const onGold = Color(0xFF1A1206);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: onGold),
          )
        else if (widget.icon != null)
          Icon(widget.icon, color: onGold, size: 22),
        if (widget.busy || widget.icon != null) const SizedBox(width: 10),
        Text(widget.label, style: AppText.label(17, weight: FontWeight.w700, color: onGold)),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  AudioService.instance.sfx(Sfx.tap);
                  widget.onPressed!();
                }
              : null,
          child: FocusableActionDetector(
            enabled: enabled,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              }),
            },
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              duration: AppMotion.micro,
              curve: AppMotion.curve,
              child: AnimatedOpacity(
                opacity: enabled || widget.busy ? 1 : 0.45,
                duration: AppMotion.micro,
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  curve: AppMotion.curve,
                  height: widget.height,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(widget.height / 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: _hover ? 0.55 : 0.35),
                        blurRadius: _hover ? 34 : 24,
                        spreadRadius: -4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: glass pill.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.height = 52,
    this.color = AppColors.text,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;
  final Color color;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final r = BorderRadius.circular(widget.height / 2);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: r,
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    AudioService.instance.sfx(Sfx.tap);
                    widget.onPressed!();
                  }
                : null,
            child: AnimatedContainer(
              duration: AppMotion.micro,
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: _hover ? AppColors.glassFillStrong : AppColors.glassFill,
                borderRadius: r,
                border: Border.all(
                    color: _hover ? AppColors.gold.withValues(alpha: 0.5) : AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: widget.color),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(15, color: widget.color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button on glass, 48px target.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 48,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: AppColors.glassFill,
          shape: const CircleBorder(side: BorderSide(color: AppColors.glassBorder)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    AudioService.instance.sfx(Sfx.tap);
                    onPressed!();
                  },
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.44, color: AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded tag.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.color = AppColors.gold, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(label, style: AppText.label(12, color: color)),
        ],
      ),
    );
  }
}

/// Selectable chip used for grid presets and filters.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sublabel,
  });

  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            AudioService.instance.sfx(Sfx.tap);
            onTap();
          },
          child: AnimatedContainer(
            duration: AppMotion.micro,
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.gold.withValues(alpha: 0.16) : AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.glassBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: AppText.label(15,
                        weight: FontWeight.w700,
                        color: selected ? AppColors.gold : AppColors.text)),
                if (sublabel != null)
                  Text(sublabel!, style: AppText.label(11, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented control on glass.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == selected,
                label: labelOf(v),
                excludeSemantics: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      AudioService.instance.sfx(Sfx.tap);
                      onChanged(v);
                    },
                    child: AnimatedContainer(
                      duration: AppMotion.short,
                      curve: AppMotion.curve,
                      height: 44,
                      decoration: BoxDecoration(
                        color: v == selected ? AppColors.gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (iconOf != null) ...[
                            Icon(iconOf!(v),
                                size: 16,
                                color: v == selected ? const Color(0xFF1A1206) : AppColors.textMuted),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              labelOf(v),
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(14,
                                  color: v == selected ? const Color(0xFF1A1206) : AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

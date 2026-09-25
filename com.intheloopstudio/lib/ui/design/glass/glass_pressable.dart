import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';

/// Press feedback for glass controls: the surface shrinks slightly and
/// brightens while touched, then springs back. Emits a light haptic on
/// release, like a native `UIButton`.
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.haptics = true,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool haptics;
  final String? semanticsLabel;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  void _set(bool v) {
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? GlassMotion.pressedScale : 1.0;
    final child = AnimatedScale(
      scale: scale,
      duration: _pressed ? GlassMotion.press : GlassMotion.release,
      curve: _pressed ? GlassMotion.ease : GlassMotion.spring,
      child: AnimatedOpacity(
        opacity: _enabled ? 1 : 0.45,
        duration: GlassMotion.reveal,
        child: widget.child,
      ),
    );

    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _set(true) : null,
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: _enabled
          ? () {
              if (widget.haptics) HapticFeedback.lightImpact();
              widget.onPressed?.call();
            }
          : null,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptics) HapticFeedback.mediumImpact();
              widget.onLongPress?.call();
            },
      child: child,
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticsLabel,
      child: gesture,
    );
  }
}

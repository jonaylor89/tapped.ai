import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_button.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';
import 'package:intheloopapp/ui/design/glass/liquid_glass.dart';

/// Modal sheet in the Liquid Glass material.
///
/// Floats above a dimmed backdrop with a grabber, optional title row and a
/// close control. The content underneath stays faintly visible through the
/// glass, which anchors the sheet to the screen it came from.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isDismissible = true,
  bool showClose = false,
  bool scrollable = false,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    showDragHandle: false,
    sheetAnimationStyle: const AnimationStyle(
      duration: GlassMotion.sheet,
      reverseDuration: GlassMotion.sheet,
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          TappedSpacing.xl,
          0,
          TappedSpacing.xl,
          TappedSpacing.xl + bottom,
        ),
        child: builder(ctx),
      );

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          TappedSpacing.sm,
          0,
          TappedSpacing.sm,
          TappedSpacing.sm,
        ),
        child: LiquidGlass(
          variant: GlassVariant.prominent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassRadius.sheet),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GlassGrabber(),
                if (title != null || showClose)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TappedSpacing.xl,
                      TappedSpacing.xs,
                      TappedSpacing.lg,
                      TappedSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: title == null
                              ? const SizedBox.shrink()
                              : Text(
                                  title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                        ),
                        if (showClose)
                          GlassIconButton(
                            icon: CupertinoIcons.xmark,
                            size: 32,
                            iconSize: 14,
                            onPressed: () => Navigator.of(ctx).pop(),
                            semanticsLabel: 'close',
                          ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: TappedSpacing.sm),
                if (scrollable)
                  Flexible(child: SingleChildScrollView(child: content))
                else
                  content,
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The little pill at the top of a sheet.
class GlassGrabber extends StatelessWidget {
  const GlassGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: TappedSpacing.sm + 2),
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// A single row in a [showGlassActionSheet].
class GlassAction {
  const GlassAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool destructive;
}

/// Native `UIAlertController` action sheet (system slide-up, blur, and
/// press feedback). Dismisses itself before invoking the action.
Future<void> showGlassActionSheet({
  required BuildContext context,
  required List<GlassAction> actions,
  String? title,
  String? message,
  String cancelLabel = 'cancel',
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: a.destructive,
            onPressed: () {
              Navigator.of(ctx).pop();
              a.onPressed();
            },
            child: Text(a.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(ctx).pop(),
        child: Text(cancelLabel),
      ),
    ),
  );
}

/// Confirmation dialog using the native Cupertino alert. Returns true when
/// the confirm action was chosen.
Future<bool> showGlassConfirm({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = 'confirm',
  String cancelLabel = 'cancel',
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

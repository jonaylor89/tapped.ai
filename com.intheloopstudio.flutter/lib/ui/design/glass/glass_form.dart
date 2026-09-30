import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_list.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';

/// Inset-grouped form, like a `UITableView` in `.insetGrouped` style with
/// text-field cells. Children are usually [GlassTextField]s and
/// [GlassListTile] pickers; they render flat and are separated by inset
/// hairlines. Validation copy belongs in [footer]/[errorText], as iOS does,
/// not inside the cells.
class GlassFormGroup extends StatelessWidget {
  const GlassFormGroup({
    required this.children,
    this.header,
    this.footer,
    this.errorText,
    this.margin = const EdgeInsets.symmetric(
      horizontal: GlassMetrics.edgeInset,
      vertical: TappedSpacing.sm,
    ),
    super.key,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final String? errorText;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: TappedSpacing.lg),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: GlassGroupedSurface.separator(context),
            ),
          ),
        );
      }
      rows.add(children[i]);
    }

    final hasError = errorText != null && errorText!.isNotEmpty;

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) GlassGroupHeader(header!),
          GlassFormScope(
            child: GlassGroupedSurface(child: Column(children: rows)),
          ),
          if (hasError)
            GlassGroupFooter(errorText!, error: true)
          else if (footer != null)
            GlassGroupFooter(footer!),
        ],
      ),
    );
  }
}

/// Marks the subtree as being inside a [GlassFormGroup] so fields render as
/// flat cells rather than wrapping themselves in a group.
class GlassFormScope extends InheritedWidget {
  const GlassFormScope({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassFormScope>() != null;

  @override
  bool updateShouldNotify(GlassFormScope oldWidget) => false;
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass_button.dart';
import 'package:intheloopapp/ui/design/glass/glass_chip.dart';
import 'package:intheloopapp/ui/design/glass/glass_list.dart';
import 'package:intheloopapp/ui/design/glass/glass_misc.dart';
import 'package:intheloopapp/ui/design/glass/glass_sheet.dart';
import 'package:intheloopapp/ui/design/glass/glass_tokens.dart';

/// A list row summarising the current selection; tapping opens a glass sheet
/// with a search field and a wrap of toggleable chips. The selection is
/// committed when the sheet's "done" button is pressed.
class GlassMultiSelect<T> extends StatelessWidget {
  const GlassMultiSelect({
    required this.title,
    required this.items,
    required this.initialValue,
    required this.labelOf,
    required this.onConfirm,
    this.leadingIcon,
    this.leadingColor,
    this.emptyLabel = 'any',
    this.searchHint = 'search',
    this.standalone = true,
    super.key,
  });

  final String title;
  final List<T> items;
  final List<T> initialValue;
  final String Function(T) labelOf;
  final void Function(List<T>) onConfirm;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final String emptyLabel;
  final String searchHint;

  /// Wrap the row in its own [GlassSection]. Pass false when composing
  /// inside an existing section.
  final bool standalone;

  String get _summary {
    if (initialValue.isEmpty) return emptyLabel;
    final labels = initialValue.map(labelOf).toList();
    if (labels.length <= 2) return labels.join(', ');
    return '${labels.take(2).join(', ')} +${labels.length - 2}';
  }

  Future<void> _open(BuildContext context) async {
    final result = await showGlassSheet<List<T>>(
      context: context,
      title: title,
      scrollable: true,
      showClose: true,
      builder: (context) => _GlassMultiSelectSheet<T>(
        items: items,
        initial: initialValue,
        labelOf: labelOf,
        searchHint: searchHint,
      ),
    );
    if (result != null) onConfirm(result);
  }

  @override
  Widget build(BuildContext context) {
    final tile = GlassListTile(
      leadingIcon: leadingIcon,
      leadingColor: leadingColor,
      title: title,
      value: _summary,
      onTap: () => _open(context),
    );
    if (!standalone) return tile;
    return GlassSection(
      margin: const EdgeInsets.symmetric(vertical: TappedSpacing.xs),
      children: [tile],
    );
  }
}

class _GlassMultiSelectSheet<T> extends StatefulWidget {
  const _GlassMultiSelectSheet({
    required this.items,
    required this.initial,
    required this.labelOf,
    required this.searchHint,
  });

  final List<T> items;
  final List<T> initial;
  final String Function(T) labelOf;
  final String searchHint;

  @override
  State<_GlassMultiSelectSheet<T>> createState() =>
      _GlassMultiSelectSheetState<T>();
}

class _GlassMultiSelectSheetState<T> extends State<_GlassMultiSelectSheet<T>> {
  late final Set<T> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.items
        : widget.items
              .where((e) => widget.labelOf(e).toLowerCase().contains(q))
              .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: GlassMetrics.edgeInset,
        right: GlassMetrics.edgeInset,
        bottom: MediaQuery.viewInsetsOf(context).bottom + TappedSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSearchField(
            hintText: widget.searchHint,
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: TappedSpacing.md),
          Row(
            children: [
              Text(
                '${_selected.length} selected',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                GlassButton.plain(
                  label: 'clear',
                  compact: true,
                  onPressed: () => setState(_selected.clear),
                ),
            ],
          ),
          const SizedBox(height: TappedSpacing.sm),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Wrap(
                spacing: TappedSpacing.sm,
                runSpacing: TappedSpacing.sm,
                children: [
                  for (final item in visible)
                    GlassChip(
                      label: widget.labelOf(item),
                      selected: _selected.contains(item),
                      onTap: () => setState(() {
                        if (!_selected.remove(item)) _selected.add(item);
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TappedSpacing.lg),
          GlassButton.primary(
            label: 'done',
            icon: CupertinoIcons.checkmark_alt,
            expand: true,
            onPressed: () => Navigator.of(context).pop(
              widget.items.where(_selected.contains).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

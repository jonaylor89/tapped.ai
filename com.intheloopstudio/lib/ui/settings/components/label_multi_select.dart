import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/label.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class LabelMultiSelect extends StatelessWidget {
  const LabelMultiSelect({
    required this.onConfirm,
    required this.initialValue,
    this.standalone = true,
    super.key,
  });

  final List<String> initialValue;
  final void Function(List<String?>) onConfirm;
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    return GlassMultiSelect<String>(
      title: 'labels',
      leadingIcon: CupertinoIcons.tag_fill,
      leadingColor: Colors.teal,
      items: labels,
      initialValue: initialValue,
      labelOf: (label) => label,
      onConfirm: onConfirm,
      searchHint: 'search labels',
      standalone: standalone,
    );
  }
}

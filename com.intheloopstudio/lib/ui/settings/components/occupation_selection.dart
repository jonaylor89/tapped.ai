import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/occupation.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class OccupationSelection extends StatelessWidget {
  const OccupationSelection({
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
      title: 'occupations',
      leadingIcon: CupertinoIcons.briefcase_fill,
      leadingColor: Colors.indigo,
      items: occupations,
      initialValue: initialValue,
      labelOf: (occupation) => occupation,
      onConfirm: onConfirm,
      searchHint: 'search occupations',
      standalone: standalone,
    );
  }
}

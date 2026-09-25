import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class GenreSelection extends StatelessWidget {
  const GenreSelection({
    required this.onConfirm,
    required this.initialValue,
    this.standalone = true,
    super.key,
  });

  final List<Genre> initialValue;
  final void Function(List<Genre?>) onConfirm;
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    return GlassMultiSelect<Genre>(
      title: 'genres',
      leadingIcon: CupertinoIcons.music_note_list,
      leadingColor: Colors.pink,
      items: Genre.values,
      initialValue: initialValue,
      labelOf: (genre) => genre.formattedName,
      onConfirm: onConfirm,
      searchHint: 'search genres',
      standalone: standalone,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/tapped_section_header.dart';

class SheetGenreChips extends StatelessWidget {
  const SheetGenreChips({required this.genreCounts, super.key});

  final Iterable<MapEntry<String, int>> genreCounts;

  @override
  Widget build(BuildContext context) {
    if (genreCounts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TappedSectionHeader('top genres in area'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: genreCounts
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TappedSpacing.xs,
                    ),
                    child: Chip(label: Text(e.key)),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

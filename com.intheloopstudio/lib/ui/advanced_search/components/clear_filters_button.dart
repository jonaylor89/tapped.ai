import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/search_bloc/search_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class ClearFiltersButton extends StatelessWidget {
  const ClearFiltersButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassButton.plain(
      label: 'clear',
      compact: true,
      onPressed: () {
        context.search.add(ClearFilters());
      },
    );
  }
}

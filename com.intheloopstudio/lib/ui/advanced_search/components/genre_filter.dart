import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/search_bloc/search_bloc.dart';
import 'package:intheloopapp/ui/settings/components/genre_selection.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class GenreFilter extends StatelessWidget {
  const GenreFilter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return GenreSelection(
          initialValue: state.genres,
          onConfirm: (values) {
            context.search.add(
              SetAdvancedSearchFilters(
                genres: values
                    .where(
                      (element) => element != null,
                    )
                    .whereType<Genre>()
                    .toList(),
              ),
            );
          },
        );
      },
    );
  }
}

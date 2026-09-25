import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/search_bloc/search_bloc.dart';
import 'package:intheloopapp/ui/advanced_search/components/clear_filters_button.dart';
import 'package:intheloopapp/ui/advanced_search/components/genre_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/label_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/location_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/occupation_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/search_button.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class AdvancedSearchView extends StatelessWidget {
  const AdvancedSearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        final activeCount =
            state.occupations.length +
            state.genres.length +
            state.labels.length +
            (state.place.isSome() ? 1 : 0);
        return GlassPage(
          title: 'filters',
          subtitle: activeCount == 0
              ? 'narrow down who you find'
              : '$activeCount active',
          actions: const [ClearFiltersButton()],
          bottomBar: const GlassBottomBar(child: SearchButton()),
          slivers: const [
            SliverToBoxAdapter(
              child: GlassSection(
                header: 'who',
                children: [
                  OccupationFilter(),
                  GenreFilter(),
                  LabelFilter(),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: GlassSection(
                header: 'where',
                children: [LocationFilter()],
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: GlassMetrics.bottomBarClearance),
            ),
          ],
        );
      },
    );
  }
}

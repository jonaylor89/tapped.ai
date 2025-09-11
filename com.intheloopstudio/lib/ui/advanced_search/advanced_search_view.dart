import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/advanced_search/components/clear_filters_button.dart';
import 'package:intheloopapp/ui/advanced_search/components/genre_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/label_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/location_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/occupation_filter.dart';
import 'package:intheloopapp/ui/advanced_search/components/search_button.dart';
import 'package:intheloopapp/ui/common/tapped_app_bar.dart';

class AdvancedSearchView extends StatelessWidget {
  const AdvancedSearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: const TappedAppBar(
        title: 'Advanced Search',
      ),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: 40,
              ),
              OccupationFilter(),
              SizedBox(
                height: 20,
              ),
              GenreFilter(),
              SizedBox(
                height: 20,
              ),
              LabelFilter(),
              SizedBox(
                height: 20,
              ),
              LocationFilter(),
              SizedBox(
                height: 20,
              ),
              SearchButton(),
              SizedBox(
                height: 20,
              ),
              ClearFiltersButton(),
            ],
          ),
        ),
      ),
    );
  }
}

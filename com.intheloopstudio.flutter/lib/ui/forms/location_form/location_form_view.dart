import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_form/location_cubit.dart';
import 'package:intheloopapp/ui/forms/location_form/location_results.dart';
import 'package:intheloopapp/ui/forms/location_form/location_search_bar.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class LocationFormView extends StatelessWidget {
  const LocationFormView({
    required this.initialPlace,
    required this.onSelected,
    super.key,
  });

  final Option<PlaceData> initialPlace;
  final void Function(
    Option<PlaceData> placeData,
    String placeId,
  )
  onSelected;

  @override
  Widget build(BuildContext context) {
    final places = RepositoryProvider.of<PlacesRepository>(context);
    return BlocProvider(
      create: (context) => LocationCubit(
        places: places,
        onSelected: onSelected,
        navigationBloc: context.nav,
      ),
      child: GlassAmbientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GlassMetrics.edgeInset,
                    TappedSpacing.sm,
                    GlassMetrics.edgeInset,
                    TappedSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: Icons.arrow_back_ios_new,
                        semanticsLabel: 'back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: TappedSpacing.sm),
                      Expanded(
                        child: LocationSearchBar(initialPlace: initialPlace),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: LocationResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

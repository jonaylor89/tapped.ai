import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_form/location_cubit.dart';

class LocationResults extends StatelessWidget {
  const LocationResults({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocationCubit, LocationState>(
      builder: (context, state) {
        if (state.loading) {
          return const Center(child: GlassLoading());
        }

        if (state.locationResults.isEmpty) {
          return const Center(
            child: GlassEmptyState(
              icon: CupertinoIcons.location,
              title: 'search a location',
              message: 'start typing a city, venue, or address',
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: TappedSpacing.xxl),
          physics: const BouncingScrollPhysics(),
          children: [
            GlassSection(
              children: [
                for (final prediction in state.locationResults)
                  GlassListTile(
                    leadingIcon: CupertinoIcons.location_fill,
                    leadingColor: TappedColors.error,
                    title: prediction.primaryText,
                    subtitle: prediction.secondaryText,
                    onTap: () {
                      context.read<LocationCubit>().saveLocation(prediction);
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

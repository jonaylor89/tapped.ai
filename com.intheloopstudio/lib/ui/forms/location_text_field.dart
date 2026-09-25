import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/utils/geohash.dart';

class LocationTextField extends StatelessWidget {
  const LocationTextField({
    required this.initialPlace,
    required this.onChanged,
    this.hintText = 'tap to select a city',
    super.key,
  });

  final void Function(
    Option<PlaceData> placeData,
    String placeId,
  )
  onChanged;
  final Option<PlaceData> initialPlace;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      title: 'location',
      value: initialPlace.match(
        () => hintText,
        (t) => formattedShortAddress(t.addressComponents),
      ),
      onTap: () {
        context.push(
          LocationFormPage(
            initialPlace: initialPlace,
            onSelected: onChanged,
          ),
        );
      },
    );
  }
}

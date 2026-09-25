import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:maps_launcher/maps_launcher.dart';

class LocationChip extends StatelessWidget {
  const LocationChip({
    required this.place,
    this.type = PlaceType.LOCALITY,
    this.defaultIdent = 'Unknown',
    super.key,
  });

  final PlaceData place;
  final PlaceType type;
  final String defaultIdent;

  @override
  Widget build(BuildContext context) {
    final fullAddress = formattedFullAddress(place.addressComponents);
    return GlassChip(
      icon: CupertinoIcons.location_solid,
      label: getAddressComponent(
        place.addressComponents,
        type: type,
        defaultIdent: defaultIdent,
      ),
      onTap: () => MapsLauncher.launchQuery(fullAddress),
    );
  }
}

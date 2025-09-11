import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:fpdart/fpdart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/places_repository.dart';
import 'package:intheloopapp/data/search_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/models/location.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/debouncer.dart';
import 'package:latlong2/latlong.dart';

part 'discover_state.dart';

part 'discover_cubit.freezed.dart';

class DiscoverCubit extends Cubit<DiscoverState> {
  DiscoverCubit({
    required this.currentUser,
    required this.search,
    required this.database,
    required this.initGenres,
    required this.onboardingBloc,
    required this.places,
    this.suggestedMaxCapacity = 1000,
  }) : super(
    DiscoverState(
      genreFilters: initGenres,
      capacityRange: RangeValues(0, suggestedMaxCapacity.toDouble()),
    ),
  );

  final UserModel currentUser;
  final SearchRepository search;
  final DatabaseRepository database;
  final List<Genre> initGenres;
  final OnboardingBloc onboardingBloc;
  final PlacesRepository places;
  final int suggestedMaxCapacity;

  final _debouncer = Debouncer(
    const Duration(milliseconds: 500),
  );

  Future<(double, double)> _determinePosition() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled don't continue
        // accessing the position and request users of the
        // App to enable the location services.
        return Future.error('Location services are disabled.');
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied, next time you could try
          // requesting permissions again (this is also where
          // Android's shouldShowRequestPermissionRationale
          // returned true. According to Android guidelines
          // your App should show an explanatory UI now.
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permissions are denied forever, handle appropriately.
        throw Exception(
          'Location permissions are permanently denied, we cannot request permissions.',
        );
      }

      // When we reach here, permissions are granted and we can
      // continue accessing the position of the device.
      final position = await Future.any([
        Geolocator.getCurrentPosition(),
        Future.delayed(const Duration(seconds: 2), () => null),
      ]);

      if (position != null) {
        final currLoc = currentUser.location;
        if (currLoc.isNone()) {
          final placeId = await places.getPlaceIdByLatLng(
            position.latitude,
            position.longitude,
          );

          placeId.map((t) {
            final user = currentUser.copyWith(
              location: Option.of(
                Location(
                  placeId: t,
                  // geohash: '',
                  lat: position.latitude,
                  lng: position.longitude,
                ),
              ),
            );
            onboardingBloc.add(
              UpdateOnboardedUser(user: user),
            );
          });
        }
      }

      return (
      position?.latitude ?? Location.nyc.lat,
      position?.longitude ?? Location.nyc.lng,
      );
    } catch (e) {
      return (Location.nyc.lat, Location.nyc.lng);
    }
  }

  Future<(double, double)> initLocation() async {
    final (lat, lng) = await _determinePosition();
    final hits = await getVenues(
      lat: lat,
      lng: lng,
    );
    emit(
      state.copyWith(
        venueHits: hits,
        userLat: lat,
        userLng: lng,
      ),
    );

    return (lat, lng);
  }

  void setGenreFilters(List<Genre> genres) {
    searchNewBounds(
      bounds: state.bounds,
      overlay: state.mapOverlay,
      genres: genres,
    );

    emit(
      state.copyWith(
        genreFilters: genres,
        mapOverlay: state.mapOverlay,
      ),
    );
  }

  void toggleGenreFilter(Genre genre) {
    final genres = List<Genre>.from(state.genreFilters);
    if (genres.contains(genre)) {
      genres.remove(genre);
    } else {
      genres.add(genre);
    }

    searchNewBounds(
      bounds: state.bounds,
      overlay: state.mapOverlay,
      genres: genres,
    );

    emit(
      state.copyWith(
        genreFilters: genres,
        mapOverlay: state.mapOverlay,
      ),
    );
  }

  void updateCapacityRange(RangeValues range) {
    emit(
      state.copyWith(
        capacityRange: range,
      ),
    );
  }

  Future<List<UserModel>> getVenues({
    double? lat,
    double? lng,
  }) async {
    try {
      final hits = await search.queryUsers(
        '',
        occupations: ['Venue', 'venue'],
        venueGenres: state.genreFilterStrings.isNotEmpty
            ? state.genreFilterStrings
            : null,
        lat: lat,
        lng: lng,
      );

      return hits;
    } catch (e, s) {
      logger.e('Error getting venues', error: e, stackTrace: s);
      return [];
    }
  }

  Future<List<Booking>> getBookings({
    double? lat,
    double? lng,
  }) async {
    final hits = await search.queryBookings(
      '',
      lat: lat,
      lng: lng,
    );
    return hits;
  }

  Future<List<Opportunity>> getOpportunities({
    double? lat,
    double? lng,
  }) async {
    final hits = await search.queryOpportunities(
      '',
      lat: lat,
      lng: lng,
      startTime: DateTime.now(),
    );
    return hits;
  }

  void onMapOverlayChange(MapOverlay overlay, {
    List<Genre>? genres,
    int? minCapacity,
    int? maxCapacity,
  }) {
    searchNewBounds(
      bounds: state.bounds,
      overlay: overlay,
      genres: genres,
      minCapacity: minCapacity,
      maxCapacity: maxCapacity,
    );


    emit(state.copyWith(mapOverlay: overlay));
  }

  void onBoundsChange(LatLngBounds? bounds) {
    emit(
      state.copyWith(
        bounds: bounds,
      ),
    );

    _debouncer.run(() async {
      emit(
        state.copyWith(
          resultsExpired: true,
        ),
      );
    });
  }

  Future<void> searchNewBounds({
    LatLngBounds? bounds,
    MapOverlay? overlay,
    List<Genre>? genres,
    int? minCapacity,
    int? maxCapacity,
  }) async {
    final searchBounds = bounds ?? state.bounds;
    if (searchBounds == null) return;

    final mapType = overlay ?? state.mapOverlay;

    final maxCap = (maxCapacity ?? state.capacityRangeEnd) == 1000
        ? 100000
        : (maxCapacity ?? state.capacityRangeEnd);

    final newGenres = genres != null
        ? genres.map((e) => e.name).toList()
        : state.genreFilterStrings;

    emit(
      state.copyWith(
        resultsExpired: false,
      ),
    );

    return (switch (mapType) {
      MapOverlay.venues =>
          () async {
        final hits = await search.queryUsersInBoundingBox(
          '',
          occupations: ['Venue', 'venue'],
          venueGenres: newGenres.isNotEmpty ? newGenres : null,
          minCapacity: minCapacity ?? state.capacityRangeStart,
          maxCapacity: maxCap,
          swLatitude: searchBounds.southWest.latitude,
          swLongitude: searchBounds.southWest.longitude,
          neLatitude: searchBounds.northEast.latitude,
          neLongitude: searchBounds.northEast.longitude,
        );
        emit(state.copyWith(venueHits: hits));
      },
      MapOverlay.opportunities =>
          () async {
        final hits = await search.queryOpportunitiesInBoundingBox(
          '',
          swLatitude: searchBounds.southWest.latitude,
          swLongitude: searchBounds.southWest.longitude,
          neLatitude: searchBounds.northEast.latitude,
          neLongitude: searchBounds.northEast.longitude,
          limit: 500,
          startTime: DateTime.now(),
        );
        emit(state.copyWith(opportunityHits: hits));
      },
    })();
  }
}
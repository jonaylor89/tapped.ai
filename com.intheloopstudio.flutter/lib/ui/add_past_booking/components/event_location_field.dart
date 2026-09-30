import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/common/venue_search_bar.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_text_field.dart';
import 'package:intheloopapp/ui/user_tile.dart';

class EventLocationField extends StatelessWidget {
  const EventLocationField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        return GlassQuestion(
          title: 'where was it?',
          caption: 'pick a venue on tapped, or search any address',
          child: switch (state.venue) {
            None() => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                VenueSearchBar(
                  onSelected: (venue) {
                    context.read<AddPastBookingCubit>().venueChanged(
                      Option.of(venue),
                    );
                  },
                ),
                const SizedBox(height: TappedSpacing.lg),
                GlassGroupedSurface(
                  child: LocationTextField(
                    hintText: 'search address',
                    initialPlace: state.place,
                    onChanged: (place, _) {
                      context.read<AddPastBookingCubit>().placeChanged(place);
                    },
                  ),
                ),
              ],
            ),
            Some(:final value) => GlassCard(
              padding: EdgeInsets.zero,
              child: UserTile(
                user: state.venue,
                userId: value.id,
                trailing: GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  size: 36,
                  iconSize: 16,
                  semanticsLabel: 'clear venue',
                  onPressed: () {
                    context.read<AddPastBookingCubit>().venueChanged(
                      const None(),
                    );
                  },
                ),
              ),
            ),
          },
        );
      },
    );
  }
}

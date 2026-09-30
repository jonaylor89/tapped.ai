import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

class RequestToPerform extends StatelessWidget {
  const RequestToPerform({
    required this.venue,
    super.key,
  });

  final UserModel venue;

  Widget _buildRequestButton(BuildContext context) {
    return PremiumBuilder(
      builder: (context, isPremium) {
        return GlassButton.primary(
          label: 'request to perform',
          icon: CupertinoIcons.music_mic,
          expand: true,
          onPressed: () {
            if (!isPremium) {
              context.push(PaywallPage());
              return;
            }

            context.push(
              RequestToPerformPage(
                venues: [venue],
                collaborators: [],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    final bookingEmail = venue.venueInfo.flatMap((t) => t.bookingEmail);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return switch (bookingEmail) {
          None() => const SizedBox.shrink(),
          Some(value: final _) => FutureBuilder(
            future: database.hasUserSentContactRequest(
              user: currentUser,
              venue: venue,
            ),
            builder: (context, snapshot) {
              final alreadyRequested = snapshot.data;
              return switch (alreadyRequested) {
                null => const GlassButton(
                  label: 'request to perform',
                  expand: true,
                  isLoading: true,
                  onPressed: null,
                ),
                false => _buildRequestButton(context),
                true => const GlassButton(
                  label: 'performance request sent',
                  icon: CupertinoIcons.checkmark_alt,
                  expand: true,
                  onPressed: null,
                ),
              };
            },
          ),
        };
      },
    );
  }
}

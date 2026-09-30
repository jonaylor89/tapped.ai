import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/data/auth_repository.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/custom_claims_builder.dart';

class RequestToBookButton extends StatelessWidget {
  const RequestToBookButton({
    required this.user,
    super.key,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        if (currentUser.id == user.id) {
          return const SizedBox.shrink();
        }

        return CustomClaimsBuilder(
          builder: (context, claims) {
            final isBooker = claims.contains(CustomClaim.booker);
            final isAdmin = claims.contains(CustomClaim.admin);
            if (!isBooker && !isAdmin) {
              return const SizedBox.shrink();
            }

            return GlassButton.primary(
              label: 'request to book',
              icon: CupertinoIcons.calendar_badge_plus,
              expand: true,
              onPressed: () => context.push(
                CreateBookingPage(
                  requesteeId: user.id,
                  service: const None(),
                  requesteeStripeConnectedAccountId:
                      user.stripeConnectedAccountId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class ApplyButton extends StatefulWidget {
  const ApplyButton({
    required this.opportunity,
    super.key,
  });

  final Opportunity opportunity;

  @override
  State<ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<ApplyButton> {
  Opportunity get _opportunity => widget.opportunity;

  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final database = context.database;

    return CurrentUserBuilder(
      builder: (context, currentUser) {
        if (currentUser.id == _opportunity.userId) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: TappedSpacing.xs,
              horizontal: GlassMetrics.edgeInset,
            ),
            child: GlassButton(
              label: "see who's interested",
              icon: CupertinoIcons.person_2,
              expand: true,
              onPressed: () => context.push(
                InterestedUsersPage(opportunity: _opportunity),
              ),
            ),
          );
        }

        return FutureBuilder<bool>(
          future: database.isUserAppliedForOpportunity(
            userId: currentUser.id,
            opportunityId: _opportunity.id,
          ),
          builder: (context, snapshot) {
            final applied = snapshot.data;
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: TappedSpacing.xs,
                horizontal: GlassMetrics.edgeInset,
              ),
              child: switch (applied) {
                null => const GlassButton.primary(
                  label: 'apply',
                  expand: true,
                  isLoading: true,
                  onPressed: null,
                ),
                true => const GlassButton(
                  label: 'applied',
                  icon: CupertinoIcons.checkmark_alt,
                  foreground: TappedColors.success,
                  expand: true,
                  onPressed: null,
                ),
                false => GlassButton.primary(
                  label: 'apply',
                  icon: CupertinoIcons.paperplane_fill,
                  expand: true,
                  isLoading: loading,
                  onPressed: () {
                    setState(() {
                      loading = true;
                    });
                    database
                        .applyForOpportunity(
                          opportunity: _opportunity,
                          userComment: '',
                          userId: currentUser.id,
                        )
                        .then((value) {
                          if (!mounted) return;
                          setState(() {
                            loading = false;
                          });
                        });
                  },
                ),
              },
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class InterestedUsersView extends StatelessWidget {
  const InterestedUsersView({
    required this.opportunity,
    super.key,
  });

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return FutureBuilder<List<UserModel>>(
      future: database.getInterestedUsers(opportunity),
      builder: (context, snapshot) {
        final interestedUsers = snapshot.data;
        return GlassPage(
          title: 'applicants',
          subtitle: interestedUsers == null
              ? opportunity.title
              : '${interestedUsers.length} · ${opportunity.title}',
          showBack: false,
          actions: [
            GlassIconButton(
              icon: CupertinoIcons.xmark,
              size: 36,
              iconSize: 16,
              semanticsLabel: 'close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          slivers: [
            if (interestedUsers == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: GlassLoading(),
              )
            else if (interestedUsers.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: GlassEmptyState(
                  icon: CupertinoIcons.person_2,
                  title: 'no applicants yet',
                  message: 'share the opportunity to reach more performers',
                ),
              )
            else
              SliverToBoxAdapter(
                child: GlassSection(
                  children: [
                    for (final interest in interestedUsers)
                      UserTile(
                        userId: interest.id,
                        user: Option.of(interest),
                      ),
                  ],
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: TappedSpacing.xxxl),
            ),
          ],
        );
      },
    );
  }
}

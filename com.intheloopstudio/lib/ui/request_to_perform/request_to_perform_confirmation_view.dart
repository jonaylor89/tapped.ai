import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/components/user_slider.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class RequestToPerformConfirmationView extends StatelessWidget {
  const RequestToPerformConfirmationView({
    required this.venues,
    super.key,
  });

  final List<UserModel> venues;

  Iterable<String> get performerIds => venues
      .map(
        (venue) => venue.venueInfo.fold(
          () => <String>[],
          (info) => info.topPerformerIds,
        ),
      )
      .flatten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final database = context.database;
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              GlassMetrics.edgeInset,
              TappedSpacing.xxl,
              GlassMetrics.edgeInset,
              GlassMetrics.bottomBarClearance + TappedSpacing.lg,
            ),
            children: [
              LiquidGlass.circle(
                width: 96,
                height: 96,
                tint: TappedColors.success,
                child: const Center(
                  child: Icon(
                    CupertinoIcons.paperplane_fill,
                    size: 40,
                    color: TappedColors.success,
                  ),
                ),
              ),
              const SizedBox(height: TappedSpacing.xl),
              Text(
                'request sent',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: TappedSpacing.sm),
              Text(
                '${venues.length} ${venues.length == 1 ? 'venue' : 'venues'}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: TappedSpacing.xl),
              GlassBanner(
                icon: CupertinoIcons.clock,
                title: 'what happens next',
                message:
                    "you'll get a dm from the venue if they accept. venues "
                    'usually take 1-2 weeks to respond. if you have questions '
                    "or they're taking too long, contact the venue directly.",
                margin: EdgeInsets.zero,
              ),
              FutureBuilder<List<UserModel>>(
                future: (() async {
                  final performerOptions = await Future.wait(
                    performerIds.map(database.getUserById),
                  );

                  final performers = performerOptions
                      .whereType<Some<UserModel>>()
                      .map((e) => e.value)
                      .toList();

                  return performers;
                })(),
                builder: (context, snapshot) {
                  if (performerIds.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: TappedSpacing.xl),
                      child: GlassLoading(),
                    );
                  }

                  final performers = snapshot.data ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: TappedSpacing.xl),
                      const GlassSectionTitle(
                        'local contacts',
                        padding: EdgeInsets.only(bottom: TappedSpacing.sm),
                      ),
                      UserSlider(users: performers),
                      const SizedBox(height: TappedSpacing.md),
                      RichText(
                        text: TextSpan(
                          text:
                              'these are the local performers we recommend '
                              'you contact on instagram. ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.75,
                            ),
                          ),
                          children: [
                            TextSpan(
                              text:
                                  "you're 85% more likely to get booked "
                                  'for a show ',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(
                              text: "if you're on a bill with a local",
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        bottomNavigationBar: GlassBottomBar(
          child: GlassButton.primary(
            label: 'okay',
            expand: true,
            onPressed: () => context.popUntilHome(),
          ),
        ),
      ),
    );
  }
}

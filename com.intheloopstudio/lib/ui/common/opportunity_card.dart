import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/ui/conditional_parent_widget.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/opportunity_feed/components/opportunity_view.dart';
import 'package:intheloopapp/utils/admin_builder.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:intheloopapp/utils/hero_image.dart';
import 'package:intheloopapp/utils/opportunity_image.dart';
import 'package:intl/intl.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:skeletons/skeletons.dart';
import 'package:uuid/uuid.dart';

class OpportunityCard extends StatefulWidget {
  const OpportunityCard({
    required this.opportunity,
    this.onOpportunityDeleted,
    super.key,
  });

  final Opportunity opportunity;
  final void Function()? onOpportunityDeleted;

  @override
  State<OpportunityCard> createState() => _OpportunityCardState();
}

class _OpportunityCardState extends State<OpportunityCard> {
  bool _isApplied = false;

  Opportunity get _opportunity => widget.opportunity;

  @override
  void initState() {
    super.initState();
    final state = context.onboarding.state;
    return switch (state) {
      Onboarded(:final currentUser) => (() {
        context.database
            .isUserAppliedForOpportunity(
              opportunityId: _opportunity.id,
              userId: currentUser.id,
            )
            .then((isApplied) {
              if (mounted) {
                setState(() {
                  _isApplied = isApplied;
                });
              }
            });
      })(),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final places = context.places;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return AdminBuilder(
          builder: (context, isAdmin) {
            return ConditionalParentWidget(
              condition: _opportunity.userId == currentUser.id || isAdmin,
              conditionalBuilder:
                  ({
                    required Widget child,
                  }) => Slidable(
                    child: child,
                  ),
              child: FutureBuilder(
                future: getOpImage(context, widget.opportunity),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return ConditionalParentWidget(
                      condition: _isApplied,
                      conditionalBuilder:
                          ({
                            required Widget child,
                          }) => child,
                      child: SkeletonListTile(),
                    );
                  }

                  final uuid = const Uuid().v4();
                  final heroImageTag =
                      'op-image-${widget.opportunity.id}-$uuid';
                  final heroTitleTag =
                      'op-title-${widget.opportunity.id}-$uuid';
                  final provider = snapshot.data!;
                  return GlassListTile(
                    onTap: () => showCupertinoModalBottomSheet<void>(
                      context: context,
                      builder: (context) => OpportunityView(
                        opportunityId: widget.opportunity.id,
                        opportunity: Option.of(widget.opportunity),
                        heroImage: HeroImage(
                          imageProvider: provider,
                          heroTag: heroImageTag,
                        ),
                        titleHeroTag: heroTitleTag,
                        onApply: () {
                          setState(() {
                            _isApplied = true;
                          });

                          Navigator.pop(context);
                        },
                        onDislike: () {
                          setState(() {
                            _isApplied = false;
                          });
                          context.pop();
                        },
                        onDismiss: () => context.pop(),
                      ),
                    ),
                    leading: Hero(
                      tag: heroImageTag,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          image: DecorationImage(
                            image: provider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    titleWidget: Text(
                      widget.opportunity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitleWidget: FutureBuilder(
                      future: places.getPlaceById(
                        widget.opportunity.location.placeId,
                      ),
                      builder: (context, snapshot) {
                        final place = snapshot.data;
                        return switch (place) {
                          null => const SkeletonLine(),
                          None() => const SizedBox.shrink(),
                          Some(:final value) => Text(
                            formattedShortAddress(
                              value.addressComponents,
                            ).toLowerCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        };
                      },
                    ),
                    trailing: _isApplied
                        ? const GlassPill(
                            label: 'applied',
                            icon: CupertinoIcons.checkmark_alt,
                            tint: TappedColors.success,
                            foreground: TappedColors.textOnImage,
                          )
                        : Text(
                            DateFormat('MMM d')
                                .format(widget.opportunity.startTime)
                                .toLowerCase(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

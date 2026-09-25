import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/components/sheet_featured_gigs.dart';
import 'package:intheloopapp/ui/discover/components/sheet_genre_chips.dart';
import 'package:intheloopapp/ui/discover/components/sheet_handle.dart';
import 'package:intheloopapp/ui/discover/components/sheet_quick_actions.dart';
import 'package:intheloopapp/ui/discover/components/sheet_results_section.dart';
import 'package:intheloopapp/ui/discover/components/sheet_top_performers.dart';
import 'package:intheloopapp/ui/discover/components/venue_fit_utils.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';
import 'package:intheloopapp/ui/profile/components/feedback_button.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

/// Three-detent Liquid Glass sheet, Apple Maps style: an inset, rounded
/// floating card at the small and mid detents that morphs into an
/// edge-attached, more opaque full-height sheet at the top detent.
///
/// [progress] is 0 at the smallest detent and 1 fully expanded; the map
/// chrome listens to it so floating controls recede as the sheet grows.
class DraggableSheet extends StatefulWidget {
  DraggableSheet({
    DraggableScrollableController? dragController,
    this.progress,
    this.initialSize = collapsed,
    super.key,
  }) : dragController = dragController ?? DraggableScrollableController();

  final DraggableScrollableController dragController;
  final ValueNotifier<double>? progress;
  final double initialSize;

  static const double collapsed = 0.12;
  static const double mid = 0.5;
  static const double expanded = 0.94;

  @override
  State<DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<DraggableSheet> {
  DraggableScrollableController get _drag => widget.dragController;

  @override
  void initState() {
    super.initState();
    _drag.addListener(_onDrag);
  }

  @override
  void dispose() {
    _drag.removeListener(_onDrag);
    super.dispose();
  }

  double get _t => _drag.isAttached
      ? ((_drag.size - DraggableSheet.collapsed) /
                (DraggableSheet.expanded - DraggableSheet.collapsed))
            .clamp(0.0, 1.0)
      : 0.0;

  void _onDrag() => widget.progress?.value = _t;

  /// Morph happens between the mid and top detents so the card stays fully
  /// detached while it is a floating overlay over the map.
  double get _morph {
    final midT =
        (DraggableSheet.mid - DraggableSheet.collapsed) /
        (DraggableSheet.expanded - DraggableSheet.collapsed);
    return Curves.easeInOut.transform(
      ((_t - midT) / (1 - midT)).clamp(0.0, 1.0),
    );
  }

  Widget _surface(BuildContext context, {required Widget child}) {
    return AnimatedBuilder(
      animation: _drag,
      builder: (context, child) {
        final m = _morph;
        final inset = lerpDouble(GlassMetrics.edgeInset, 0, m)!;
        final radius = lerpDouble(GlassRadius.sheet, 12, m)!;
        return Padding(
          padding: EdgeInsets.fromLTRB(inset, 0, inset, inset),
          child: LiquidGlass(
            variant: GlassVariant.prominent,
            solidity: m,
            shape: RoundedRectangleBorder(
              borderRadius: m < 1
                  ? BorderRadius.circular(radius)
                  : BorderRadius.vertical(top: Radius.circular(radius)),
            ),
            child: child!,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            return FutureBuilder(
              future: database.getFeaturedOpportunities(),
              builder: (context, snapshot) {
                final featuredOpportunities = snapshot.data ?? [];
                return BlocBuilder<DiscoverCubit, DiscoverState>(
                  builder: (context, state) {
                    final sortedVenueHits = sortVenuesByFit(
                      currentUser,
                      state.venueHits,
                    );
                    final topPerformerIds = sortedVenueHits
                        .expand((v) {
                          return v.venueInfo.fold(
                            () => <String>[],
                            (t) => t.topPerformerIds,
                          );
                        })
                        .toSet()
                        .toList();
                    return FutureBuilder(
                      future: (() async {
                        final performers =
                            (await Future.wait(
                                  topPerformerIds.map(database.getUserById),
                                ))
                                .whereType<Some<UserModel>>()
                                .map((e) => e.value)
                                .toList();

                        return performers;
                      })(),
                      builder: (context, snapshot) {
                        final performers = snapshot.data ?? [];
                        return DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: widget.initialSize,
                          minChildSize: DraggableSheet.collapsed,
                          maxChildSize: DraggableSheet.expanded,
                          snap: true,
                          snapSizes: const [
                            DraggableSheet.collapsed,
                            DraggableSheet.mid,
                            DraggableSheet.expanded,
                          ],
                          snapAnimationDuration: GlassMotion.sheet,
                          controller: _drag,
                          builder: (ctx, scrollController) => _surface(
                            ctx,
                            child: Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: scrollController,
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SheetHandle(
                                          currentUser: currentUser,
                                          state: state,
                                        ),
                                        SheetQuickActions(
                                          currentUserId: currentUser.id,
                                        ),
                                        const SizedBox(
                                          height: TappedSpacing.lg,
                                        ),
                                        SheetResultsSection(
                                          currentUser: currentUser,
                                          state: state,
                                          sortedVenueHits: sortedVenueHits,
                                        ),
                                        SheetGenreChips(
                                          genreCounts: state.genreCounts,
                                        ),
                                        SheetTopPerformers(
                                          performers: performers,
                                          isPremium: isPremium,
                                        ),
                                        SheetFeaturedGigs(
                                          opportunities: featuredOpportunities,
                                        ),
                                        const SizedBox(
                                          height: TappedSpacing.md,
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: TappedSpacing.lg,
                                            horizontal: TappedSpacing.xl,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: FeedbackButton(),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(
                                          height: GlassMetrics.edgeInset * 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/common/opportunity_card.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/discover/components/venue_fit_utils.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';
import 'package:intheloopapp/ui/opportunities/opportunities_results_view.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class SheetResultsSection extends StatelessWidget {
  const SheetResultsSection({
    required this.currentUser,
    required this.state,
    required this.sortedVenueHits,
    super.key,
  });

  final UserModel currentUser;
  final DiscoverState state;
  final List<UserModel> sortedVenueHits;

  Widget _venueTile(UserModel venue) {
    final fit = isVenueGoodFit(currentUser, venue);
    return UserTile(
      userId: venue.id,
      user: Option.of(venue),
      trailing: fit
          ? Text(
              'for you',
              style: TappedTypography.bodyLg.copyWith(
                color: TappedColors.success,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (state.mapOverlay) {
      MapOverlay.venues => _VenueResults(
          sortedVenueHits: sortedVenueHits,
          venueTileBuilder: _venueTile,
        ),
      MapOverlay.opportunities => _OpportunityResults(
          opportunities: state.opportunityHits,
        ),
    };
  }
}

class _VenueResults extends StatelessWidget {
  const _VenueResults({
    required this.sortedVenueHits,
    required this.venueTileBuilder,
  });

  final List<UserModel> sortedVenueHits;
  final Widget Function(UserModel) venueTileBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...sortedVenueHits.take(3).map(venueTileBuilder),
        if (sortedVenueHits.length > 3)
          _ViewAllButton(
            onTap: () => showCupertinoModalBottomSheet<void>(
              context: context,
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('venues')),
                body: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: TappedSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: ListView.builder(
                    itemCount: sortedVenueHits.length,
                    itemBuilder: (context, index) =>
                        venueTileBuilder(sortedVenueHits[index]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OpportunityResults extends StatelessWidget {
  const _OpportunityResults({required this.opportunities});

  final List<Opportunity> opportunities;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...opportunities.take(3).map(
              (op) => OpportunityCard(opportunity: op),
            ),
        _ViewAllButton(
          onTap: () => showCupertinoModalBottomSheet<void>(
            context: context,
            builder: (context) => OpportunitiesResultsView(
              ops: opportunities,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: TappedSpacing.sm),
            child: Text(
              'view all',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

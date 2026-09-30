import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/gig_search/gig_search_cubit.dart';
import 'package:intheloopapp/ui/user_tile.dart';

/// Venue picker. Rows toggle selection; a glass bottom bar tracks the count
/// and hands the selection off to the request-to-perform flow.
class GigSearchResultsView extends StatelessWidget {
  const GigSearchResultsView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<GigSearchCubit, GigSearchState>(
      builder: (context, state) {
        final cubit = context.read<GigSearchCubit>();
        final selectedCount = state.selectedResults.length;
        return GlassPage(
          title: 'venues',
          subtitle: 'found ${state.results.length}',
          leading: GlassIconButton(
            icon: CupertinoIcons.chevron_back,
            semanticsLabel: 'back to filters',
            onPressed: cubit.resetForm,
          ),
          actions: [
            GlassButton.plain(
              label: state.allSelected ? 'deselect all' : 'select all',
              compact: true,
              onPressed: state.results.isEmpty
                  ? null
                  : () => cubit.selectAll(!state.allSelected),
            ),
          ],
          bottomBar: GlassBottomBar(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedCount == 0
                        ? 'pick the venues to reach out to'
                        : '$selectedCount selected',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                GlassButton.primary(
                  label: 'continue',
                  icon: CupertinoIcons.arrow_right,
                  onPressed: selectedCount == 0
                      ? null
                      : () {
                          context.push(
                            RequestToPerformPage(
                              venues: state.selectedResults,
                              collaborators: state.collaborators,
                            ),
                          );
                        },
                ),
              ],
            ),
          ),
          slivers: [
            if (state.results.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: GlassEmptyState(
                  icon: CupertinoIcons.building_2_fill,
                  title: 'no venues found',
                  message: 'try widening the capacity range or genres',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: TappedSpacing.sm),
                sliver: SliverList.builder(
                  itemCount: state.results.length,
                  itemBuilder: (context, index) {
                    final selectableResult = state.results[index];
                    final venue = selectableResult.user;
                    final selected = selectableResult.selected;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GlassMetrics.edgeInset,
                        vertical: TappedSpacing.xs,
                      ),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        tint: selected ? theme.colorScheme.primary : null,
                        child: UserTile(
                          userId: venue.id,
                          user: Option.of(venue),
                          showFollowButton: false,
                          onTap: () =>
                              cubit.updateSelected(venue.id, !selected),
                          trailing: AnimatedSwitcher(
                            duration: GlassMotion.press,
                            child: Icon(
                              selected
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              key: ValueKey(selected),
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(
                                      alpha: 0.3,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: GlassMetrics.bottomBarClearance),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/opportunity_bloc/opportunity_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/opportunity_feed/components/opportunity_view.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/opportunity_image.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:intl/intl.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:quiver/iterables.dart';

class OpportunitiesResultsView extends StatefulWidget {
  const OpportunitiesResultsView({
    required this.ops,
    super.key,
  });

  final List<Opportunity> ops;

  @override
  State<OpportunitiesResultsView> createState() =>
      _OpportunitiesResultsViewState();
}

class _OpportunitiesResultsViewState extends State<OpportunitiesResultsView> {
  List<SelectableResult> selectableResults = [];

  bool get allSelected => selectableResults.every((result) => result.selected);

  bool get anySelected => selectableResults.any((result) => result.selected);

  @override
  void initState() {
    super.initState();
    selectableResults = widget.ops.map((op) {
      return SelectableResult(
        op: op,
        selected: false,
      );
    }).toList();
  }

  void _setAll(bool selected) {
    setState(() {
      selectableResults = selectableResults
          .map((r) => SelectableResult(op: r.op, selected: selected))
          .toList();
    });
  }

  void _toggle(Opportunity op, bool selected) {
    setState(() {
      selectableResults = selectableResults
          .map(
            (r) => r.op.id == op.id
                ? SelectableResult(op: r.op, selected: selected)
                : r,
          )
          .toList();
    });
  }

  Future<void> _apply(
    BuildContext context, {
    required bool hasEnoughQuota,
    required String currentUserId,
  }) async {
    final nav = context.nav;
    final opBloc = context.opportunities;
    final database = context.database;

    if (!hasEnoughQuota) {
      context
        ..pop()
        ..push(PaywallPage());
      return;
    }

    final selected = selectableResults.where((r) => r.selected).toList();
    final isAppliedBatch = await Future.wait(
      selected.map(
        (result) => database.isUserAppliedForOpportunity(
          opportunityId: result.op.id,
          userId: currentUserId,
        ),
      ),
    );

    final resultsToApply = zip([selected, isAppliedBatch])
        .where((zipped) {
          final result = zipped[0] as SelectableResult;
          final isApplied = zipped[1] as bool;
          return !isApplied && result.selected;
        })
        .map((zipped) => (zipped[0] as SelectableResult).op)
        .toList();

    await EasyLoading.show(
      status: 'applying to opportunities...',
      maskType: EasyLoadingMaskType.black,
    );
    try {
      opBloc.add(
        BatchApplyForOpportunities(
          opportunities: resultsToApply,
          userComment: '',
        ),
      );
      nav.pop();
    } catch (e, s) {
      await EasyLoading.showError(e.toString());
      logger.error(
        'error applying to opportunities',
        error: e,
        stackTrace: s,
      );
    } finally {
      await EasyLoading.dismiss();
    }
  }

  Widget _row(
    BuildContext context, {
    required SelectableResult result,
    required String currentUserId,
  }) {
    final theme = Theme.of(context);
    final database = context.database;
    final op = result.op;
    final startTime = DateFormat(
      DateFormat.YEAR_ABBR_MONTH_WEEKDAY_DAY,
    ).format(op.startTime);

    return FutureBuilder(
      future: database.isUserAppliedForOpportunity(
        opportunityId: op.id,
        userId: currentUserId,
      ),
      builder: (context, snapshot) {
        final isApplied = snapshot.data;
        return GlassListTile(
          leading: FutureBuilder(
            future: getOpImage(context, op),
            builder: (context, snapshot) {
              final provider = snapshot.data;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: provider == null
                      ? const LiquidGlass(
                          variant: GlassVariant.clear,
                          shadow: false,
                          child: SizedBox.expand(),
                        )
                      : Image(image: provider, fit: BoxFit.cover),
                ),
              );
            },
          ),
          title: op.title,
          subtitle: startTime,
          showChevron: false,
          onTap: () {
            showCupertinoModalBottomSheet<void>(
              context: context,
              builder: (context) => OpportunityView(
                opportunityId: op.id,
                opportunity: Option.of(op),
                onDislike: context.pop,
              ),
            );
          },
          trailing: switch (isApplied) {
            null => const CupertinoActivityIndicator(),
            true => const GlassPill(
              label: 'applied',
              tint: TappedColors.success,
              foreground: TappedColors.success,
            ),
            false => GlassPressable(
              semanticsLabel:
                  '${result.selected ? 'deselect' : 'select'} ${op.title}',
              onPressed: () => _toggle(op, !result.selected),
              child: Padding(
                padding: const EdgeInsets.all(TappedSpacing.xs),
                child: Icon(
                  result.selected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: result.selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return PremiumBuilder(
          builder: (context, isPremium) {
            return BlocBuilder<OpportunityBloc, OpportunityState>(
              builder: (context, state) {
                final selectedCount = selectableResults
                    .where((r) => r.selected)
                    .length;
                final hasEnoughQuota =
                    isPremium || state.opQuota >= selectedCount;
                return GlassPage(
                  title: 'opportunities',
                  subtitle: 'found ${selectableResults.length}',
                  showBack: false,
                  actions: [
                    GlassButton.plain(
                      label: allSelected ? 'deselect all' : 'select all',
                      compact: true,
                      onPressed: selectableResults.isEmpty
                          ? null
                          : () => _setAll(!allSelected),
                    ),
                  ],
                  bottomBar: GlassBottomBar(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedCount == 0
                                ? 'select gigs to apply in one go'
                                : '$selectedCount selected'
                                      '${isPremium ? '' : ' · ${state.opQuota} left'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                        GlassButton.primary(
                          label: hasEnoughQuota ? 'apply' : 'upgrade',
                          icon: hasEnoughQuota
                              ? CupertinoIcons.paperplane_fill
                              : CupertinoIcons.lock_fill,
                          onPressed: anySelected
                              ? () => _apply(
                                  context,
                                  hasEnoughQuota: hasEnoughQuota,
                                  currentUserId: currentUser.id,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  slivers: [
                    if (selectableResults.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: GlassEmptyState(
                          icon: CupertinoIcons.sparkles,
                          title: 'no opportunities here',
                          message: 'try another area on the map',
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: GlassSection(
                          children: [
                            for (final result in selectableResults)
                              _row(
                                context,
                                result: result,
                                currentUserId: currentUser.id,
                              ),
                          ],
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: GlassMetrics.bottomBarClearance),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class SelectableResult {
  const SelectableResult({
    required this.op,
    required this.selected,
  });

  final Opportunity op;
  final bool selected;
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/opportunity_feed/components/apply_animation_view.dart';
import 'package:intheloopapp/ui/opportunity_feed/components/opportunity_view.dart';
import 'package:intheloopapp/ui/opportunity_feed/cubit/opportunity_feed_cubit.dart';

class OpportunityFeed extends StatelessWidget {
  const OpportunityFeed({super.key});

  Widget _buildEmptyFeed(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(GlassMetrics.edgeInset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GlassRadius.sheet),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Image(
                image: AssetImage('assets/classic_edm.gif'),
                fit: BoxFit.cover,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: GlassMetrics.edgeInset,
                right: GlassMetrics.edgeInset,
                bottom: GlassMetrics.edgeInset,
                child: LiquidGlass(
                  variant: GlassVariant.clear,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassRadius.card),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(TappedSpacing.xl),
                    child: Column(
                      children: [
                        Text(
                          "you're all caught up",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontFamily: 'Rubik One',
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: TappedSpacing.sm),
                        Text(
                          "you've gone through every gig opportunity in your area. check back soon.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OpportunityFeedCubit, OpportunityFeedState>(
      builder: (context, state) {
        if (state.loading) {
          return const GlassLoading();
        }

        if (state.showApplyAnimation) {
          return const ApplyAnimationView();
        }

        if (state.opportunities.isEmpty ||
            state.curOp >= state.opportunities.length) {
          return _buildEmptyFeed(context);
        }

        final curOp = state.opportunities[state.curOp];
        return OpportunityView(
          opportunityId: curOp.id,
          opportunity: Option.of(curOp),
          showAppBar: false,
          onDislike: () =>
              context.read<OpportunityFeedCubit>().dislikeOpportunity(),
          onApply: () => context.read<OpportunityFeedCubit>().likeOpportunity(),
          onDismiss: () =>
              context.read<OpportunityFeedCubit>().dismissOpportunity(),
        );
      },
    );
  }
}

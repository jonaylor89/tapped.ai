import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/geohash.dart';

/// Final step: a preview of the booking exactly as it will appear on the
/// profile, rendered as a glass ticket.
class ImportSummary extends StatelessWidget {
  const ImportSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        final location = switch (state.venue) {
          Some(:final value) => GlassCard(
            padding: EdgeInsets.zero,
            variant: GlassVariant.clear,
            child: UserTile(
              user: state.venue,
              userId: value.id,
            ),
          ),
          None() => switch (state.place) {
            None() => null,
            Some(:final value) => GlassListTile(
              leadingIcon: CupertinoIcons.location_solid,
              leadingColor: theme.colorScheme.primary,
              title: formattedFullAddress(value.addressComponents),
              showChevron: false,
            ),
          },
        };

        return GlassQuestion(
          title: 'looks right?',
          caption: 'this is how it will show up on your profile',
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                switch (state.flierFile) {
                  None() => const SizedBox.shrink(),
                  Some(:final value) => ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(GlassRadius.card),
                    ),
                    child: Image.file(
                      value,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                },
                Padding(
                  padding: const EdgeInsets.all(GlassMetrics.edgeInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      switch (state.eventName) {
                        None() => const SizedBox.shrink(),
                        Some(:final value) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: TappedSpacing.xs,
                          ),
                          child: Text(
                            value,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Rubik One',
                            ),
                          ),
                        ),
                      },
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.calendar,
                            size: 16,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          const SizedBox(width: TappedSpacing.xs),
                          Text(
                            '${state.formattedStartDate} · '
                            '${state.formattedStartTime}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (location != null) ...[
                        const SizedBox(height: TappedSpacing.md),
                        location,
                      ],
                      if (state.amountPaid > 0) ...[
                        const SizedBox(height: TappedSpacing.lg),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                state.formattedAmount,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Rubik Mono One',
                                  color: TappedColors.success,
                                ),
                              ),
                              Text(
                                'compensation',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.55,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

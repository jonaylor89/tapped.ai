import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/admin/create_opportunity_cubit.dart';
import 'package:intheloopapp/ui/common/venue_search_bar.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_text_field.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/default_image.dart';

class CreateOpportunityForm extends StatelessWidget {
  const CreateOpportunityForm({super.key});

  void _showDialog(BuildContext context, Widget child) {
    showGlassSheet<void>(
      context: context,
      builder: (BuildContext context) => SizedBox(
        height: 216,
        child: CupertinoTheme(
          data: CupertinoTheme.of(context).copyWith(
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  ImageProvider _displayPickedImage(
    Option<File> newProfileImage,
    Option<String> currentProfileImage,
  ) {
    return switch (newProfileImage) {
      Some(:final value) => FileImage(value),
      None() => switch (currentProfileImage) {
        Some(:final value) => CachedNetworkImageProvider(value),
        None() => getDefaultImage(const None()),
      },
    };
  }

  Widget _flier(BuildContext context, CreateOpportunityState state) {
    final theme = Theme.of(context);
    final cubit = context.read<CreateOpportunityCubit>();
    return GlassPressable(
      semanticsLabel: 'upload flier',
      onPressed: cubit.handleImageFromGallery,
      child: LiquidGlass(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassRadius.card),
        ),
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GlassRadius.card - 5),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image: _displayPickedImage(state.pickedPhoto, const None()),
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                Center(
                  child: LiquidGlass.capsule(
                    height: 40,
                    padding: const EdgeInsets.symmetric(
                      horizontal: TappedSpacing.lg,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.camera_fill,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: TappedSpacing.sm),
                        Text(
                          state.pickedPhoto.isSome()
                              ? 'change flier'
                              : 'upload flier',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    CreateOpportunityState state,
  ) async {
    if (state.loading) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final value = await context.read<CreateOpportunityCubit>().submit().onError(
      (error, stackTrace) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: TappedColors.error,
            content: Text('error: $error'),
          ),
        );

        return const None();
      },
    );

    if (!context.mounted) return;
    switch (value) {
      case None():
        context.pop();
      case Some(:final value):
        context
          ..pop()
          ..push(
            OpportunityPage(
              opportunityId: value.id,
              opportunity: Option.of(value),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateOpportunityCubit, CreateOpportunityState>(
      builder: (context, state) {
        final cubit = context.read<CreateOpportunityCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
              ),
              child: _flier(context, state),
            ),
            const SizedBox(height: TappedSpacing.lg),
            GlassFormGroup(
              header: 'details',
              children: [
                GlassTextField(
                  label: 'title',
                  hintText: 'open mic night',
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: cubit.updateTitle,
                ),
                GlassTextField(
                  hintText: 'add a description',
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  maxLength: 256,
                  onChanged: cubit.updateDescription,
                ),
              ],
            ),
            GlassSection(
              header: 'where',
              footer: state.venue.isNone()
                  ? 'pick a venue on tapped, or drop a pin if they’re not '
                        'on here yet'
                  : null,
              children: [
                switch (state.venue) {
                  None() => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(TappedSpacing.md),
                        child: VenueSearchBar(
                          onSelected: (venue) {
                            cubit.updateVenue(Option.of(venue));
                          },
                        ),
                      ),
                      LocationTextField(
                        initialPlace: state.placeData,
                        onChanged: cubit.onLocationChanged,
                      ),
                    ],
                  ),
                  Some(:final value) => UserTile(
                    user: state.venue,
                    userId: value.id,
                    trailing: GlassIconButton(
                      icon: CupertinoIcons.xmark,
                      semanticsLabel: 'remove venue',
                      onPressed: () => cubit.updateVenue(const None()),
                    ),
                  ),
                },
              ],
            ),
            GlassSection(
              header: 'pay',
              children: [
                Padding(
                  padding: const EdgeInsets.all(TappedSpacing.md),
                  child: GlassSegmentedControl<bool>(
                    segments: const {
                      false: GlassSegment(
                        label: 'unpaid',
                        icon: CupertinoIcons.xmark,
                      ),
                      true: GlassSegment(
                        label: 'paid',
                        icon: CupertinoIcons.money_dollar,
                      ),
                    },
                    selected: state.isPaid,
                    onChanged: (value) => cubit.updatePaid(isPaid: value),
                  ),
                ),
              ],
            ),
            GlassSection(
              header: 'when',
              footer:
                  "if you don't know the exact start and end time, just "
                  'get the date right',
              children: [
                GlassListTile(
                  leadingIcon: CupertinoIcons.play_fill,
                  leadingColor: TappedColors.success,
                  title: 'start time',
                  value: state.formattedStartTime,
                  showChevron: false,
                  onTap: () => _showDialog(
                    context,
                    CupertinoDatePicker(
                      initialDateTime: state.startTime.value,
                      minimumDate: DateTime.now().subtract(
                        const Duration(hours: 1),
                      ),
                      use24hFormat: true,
                      onDateTimeChanged: cubit.updateStartTime,
                    ),
                  ),
                ),
                GlassListTile(
                  leadingIcon: CupertinoIcons.stop_fill,
                  leadingColor: TappedColors.error,
                  title: 'end time',
                  value: state.formattedEndTime,
                  showChevron: false,
                  onTap: () => _showDialog(
                    context,
                    CupertinoDatePicker(
                      initialDateTime: state.endTime.value,
                      minimumDate: state.startTime.value,
                      use24hFormat: true,
                      onDateTimeChanged: cubit.updateEndTime,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GlassMetrics.edgeInset,
                TappedSpacing.md,
                GlassMetrics.edgeInset,
                GlassMetrics.bottomBarClearance,
              ),
              child: GlassButton.primary(
                label: 'full send',
                icon: CupertinoIcons.paperplane_fill,
                expand: true,
                isLoading: state.loading,
                onPressed: () => _submit(context, state),
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/hero_image.dart';

class UploadFlierField extends StatelessWidget {
  const UploadFlierField({super.key});

  Widget _buildUploadButton(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return GlassCard(
      onTap: () {
        context.read<AddPastBookingCubit>().handleImageFromGallery();
      },
      semanticsLabel: 'upload flier',
      padding: const EdgeInsets.symmetric(vertical: TappedSpacing.xxl),
      child: Column(
        children: [
          LiquidGlass.circle(
            width: 64,
            height: 64,
            tint: theme.colorScheme.primary,
            child: Center(
              child: Icon(
                CupertinoIcons.photo_on_rectangle,
                size: 28,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: TappedSpacing.md),
          Text(
            'upload a flier or poster',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'optional · tap to pick from your photos',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        return GlassQuestion(
          title: 'got a flier?',
          caption: 'fliers make your booking history pop on your profile',
          child: switch (state.flierFile) {
            None() => _buildUploadButton(context),
            Some(:final value) => Stack(
              children: [
                GlassPressable(
                  onPressed: () => context.push(
                    ImagePage(
                      heroImage: HeroImage(
                        heroTag: 'flier',
                        imageProvider: FileImage(value),
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: GlassRadius.cardAll,
                    child: Image.file(
                      value,
                      height: 320,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: TappedSpacing.sm,
                  right: TappedSpacing.sm,
                  child: GlassIconButton(
                    icon: CupertinoIcons.trash_fill,
                    variant: GlassVariant.clear,
                    color: TappedColors.error,
                    semanticsLabel: 'remove flier',
                    onPressed: () =>
                        context.read<AddPastBookingCubit>().removeFlier(),
                  ),
                ),
              ],
            ),
          },
        );
      },
    );
  }
}

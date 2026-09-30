import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class BookingConfirmationView extends StatelessWidget {
  const BookingConfirmationView({
    required this.booking,
    super.key,
  });

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassAmbientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TappedSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              LiquidGlass.circle(
                width: 128,
                height: 128,
                tint: TappedColors.success,
                child: const Center(
                  child: Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 64,
                    color: TappedColors.success,
                  ),
                ),
              ),
              const SizedBox(height: TappedSpacing.xl),
              Text(
                'booking requested',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: TappedSpacing.lg),
              GlassCard(
                child: Text(
                  'your booking will be confirmed once the performer accepts.'
                  '\n\nin the meantime, a dm channel has been created for you '
                  'and the performer, and an email containing additional '
                  'steps has been sent to you.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              GlassButton.primary(
                label: 'okay',
                expand: true,
                onPressed: () {
                  context
                    ..pop()
                    ..pop()
                    ..pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

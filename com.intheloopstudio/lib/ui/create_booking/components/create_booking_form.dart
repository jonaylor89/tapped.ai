import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/create_booking/components/booking_name_text_field.dart';
import 'package:intheloopapp/ui/create_booking/components/booking_note_text_field.dart';
import 'package:intheloopapp/ui/create_booking/create_booking_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/forms/location_text_field.dart';
import 'package:intheloopapp/ui/forms/rate_text_field.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class CreateBookingForm extends StatefulWidget {
  const CreateBookingForm({super.key});

  @override
  State<CreateBookingForm> createState() => _CreateBookingFormState();
}

class _CreateBookingFormState extends State<CreateBookingForm> {
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

  final bookingNameController = TextEditingController();
  final noteController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nav = context.nav;
    return BlocBuilder<CreateBookingCubit, CreateBookingState>(
      builder: (context, state) {
        return Form(
          key: state.formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GlassMetrics.edgeInset,
            ),
            child: Column(
              children: [
                BookingNameTextField(
                  controller: bookingNameController,
                ),
                const SizedBox(height: TappedSpacing.sm),
                LocationTextField(
                  initialPlace: state.place,
                  onChanged: (place, placeId) {
                    context.read<CreateBookingCubit>().updatePlace(
                      place: place,
                      placeId: Option.of(placeId),
                    );
                  },
                ),
                GlassSection(
                  header: 'when',
                  margin: const EdgeInsets.symmetric(
                    vertical: TappedSpacing.sm,
                  ),
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
                          onDateTimeChanged: (DateTime newDateTime) {
                            context.read<CreateBookingCubit>().updateStartTime(
                              newDateTime,
                            );
                          },
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
                          onDateTimeChanged: (DateTime newDateTime) {
                            context.read<CreateBookingCubit>().updateEndTime(
                              newDateTime,
                            );
                          },
                        ),
                      ),
                    ),
                    GlassListTile(
                      leadingIcon: CupertinoIcons.timer,
                      leadingColor: theme.colorScheme.primary,
                      title: 'duration',
                      value: state.formattedDuration,
                    ),
                  ],
                ),
                GlassSection(
                  header: 'cost',
                  margin: const EdgeInsets.symmetric(
                    vertical: TappedSpacing.sm,
                  ),
                  children: [
                    GlassListTile(
                      leadingIcon: CupertinoIcons.music_mic,
                      leadingColor: Colors.purple,
                      title: state.rateType == RateType.fixed
                          ? 'performer rate'
                          :
                            // ignore: lines_longer_than_80_chars
                            'performer rate (\$${(state.rate / 100).toStringAsFixed(2)}${state.rateType == RateType.hourly ? '/hr' : ''})',
                      value: state.formattedArtistRate,
                      showChevron: state.service.isNone(),
                      onTap: switch (state.service) {
                        Some() => null,
                        None() => () {
                          final cubit = context.read<CreateBookingCubit>();
                          showGlassSheet<void>(
                            context: context,
                            title: 'performer rate',
                            builder: (context) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: GlassMetrics.edgeInset,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RateTextField(
                                      initialValue: state.rate,
                                      onChanged: cubit.updateRate,
                                    ),
                                    const SizedBox(height: TappedSpacing.md),
                                    GlassButton.primary(
                                      label: 'done',
                                      expand: true,
                                      onPressed: () {
                                        Navigator.of(context).pop(0);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      },
                    ),
                    if (state.bookingFee > 0)
                      GlassListTile(
                        leadingIcon: CupertinoIcons.percent,
                        leadingColor: Colors.orange,
                        title: 'booking fee (${state.bookingFee * 100}%)',
                        value: state.formattedApplicationFee,
                      ),
                    GlassListTile(
                      leadingIcon: CupertinoIcons.money_dollar_circle_fill,
                      leadingColor: TappedColors.success,
                      titleWidget: Text(
                        'total',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: Text(
                        state.formattedTotal,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                BookingNoteTextField(
                  controller: noteController,
                ),
                const SizedBox(height: TappedSpacing.lg),
                GlassButton.primary(
                  label: state.totalCost > 0 ? 'purchase' : 'request performer',
                  icon: state.totalCost > 0
                      ? CupertinoIcons.creditcard_fill
                      : CupertinoIcons.paperplane_fill,
                  expand: true,
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      final booking = await context
                          .read<CreateBookingCubit>()
                          .createBooking();
                      nav.push(
                        BookingConfirmationPage(booking: booking),
                      );
                    } on StripeException catch (e, s) {
                      if (e.error.code == FailureCode.Canceled) {
                        return;
                      }

                      logger.error(
                        'error create booking',
                        error: e,
                        stackTrace: s,
                      );
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.red,
                          content: Text('Error: ${e.error.localizedMessage}'),
                        ),
                      );
                    } catch (e, s) {
                      logger.error(
                        'error create booking',
                        error: e,
                        stackTrace: s,
                      );
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.red,
                          content: Text('Error making payment'),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: TappedSpacing.sm),
                if (state.totalCost > 0)
                  Text(
                    'powered by stripe',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

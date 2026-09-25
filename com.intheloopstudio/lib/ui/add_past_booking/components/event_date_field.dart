import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class EventDateField extends StatelessWidget {
  const EventDateField({
    super.key,
  });

  Future<void> _pickDate(
    BuildContext context,
    AddPastBookingState state,
  ) async {
    final theDate = await showDatePicker(
      context: context,
      initialDate: state.eventStart,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365 * 10),
      ),
      lastDate: DateTime.now().add(
        const Duration(days: 365),
      ),
    );

    if (theDate == null || !context.mounted) {
      return;
    }

    context.read<AddPastBookingCubit>().updateStartTime(
      DateTime(
        theDate.year,
        theDate.month,
        theDate.day,
        state.eventStart.hour,
        state.eventStart.minute,
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    AddPastBookingState state,
  ) async {
    final theTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(state.eventStart),
    );

    if (theTime == null || !context.mounted) {
      return;
    }

    context.read<AddPastBookingCubit>().updateStartTime(
      DateTime(
        state.eventStart.year,
        state.eventStart.month,
        state.eventStart.day,
        theTime.hour,
        theTime.minute,
      ),
    );
  }

  void _pickDuration(BuildContext context, AddPastBookingState state) {
    final cubit = context.read<AddPastBookingCubit>();
    showGlassSheet<void>(
      context: context,
      title: 'duration',
      showClose: true,
      builder: (context) => SizedBox(
        height: 216,
        child: CupertinoTheme(
          data: CupertinoTheme.of(context).copyWith(
            textTheme: CupertinoTextThemeData(
              pickerTextStyle: TextStyle(
                fontSize: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hm,
            initialTimerDuration: state.duration,
            onTimerDurationChanged: cubit.updateDuration,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        return GlassQuestion(
          title: 'when was it?',
          caption: 'the date, start time, and how long you played',
          child: GlassSection(
            margin: EdgeInsets.zero,
            children: [
              GlassListTile(
                leadingIcon: CupertinoIcons.calendar,
                leadingColor: theme.colorScheme.primary,
                title: 'date',
                value: state.formattedStartDate,
                showChevron: false,
                onTap: () => _pickDate(context, state),
              ),
              GlassListTile(
                leadingIcon: CupertinoIcons.clock_fill,
                leadingColor: Colors.orange,
                title: 'time',
                value: state.formattedStartTime,
                showChevron: false,
                onTap: () => _pickTime(context, state),
              ),
              GlassListTile(
                leadingIcon: CupertinoIcons.timer,
                leadingColor: TappedColors.success,
                title: 'duration',
                value: state.formattedDuration,
                showChevron: false,
                onTap: () => _pickDuration(context, state),
              ),
            ],
          ),
        );
      },
    );
  }
}

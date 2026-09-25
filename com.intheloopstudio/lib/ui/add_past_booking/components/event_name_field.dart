import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class EventNameField extends StatelessWidget {
  const EventNameField({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AddPastBookingCubit, AddPastBookingState>(
      builder: (context, state) {
        return GlassQuestion(
          title: 'what was it called?',
          caption: 'optional · the event or show name',
          child: GlassTextField(
            initialValue: state.eventName.getOrElse(() => ''),
            hintText: 'something in the water',
            prefixIcon: CupertinoIcons.music_note_2,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (input) =>
                context.read<AddPastBookingCubit>().eventNameChanged(input),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/create_booking/create_booking_cubit.dart';

class BookingNameTextField extends StatelessWidget {
  const BookingNameTextField({
    this.controller,
    super.key,
  });

  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateBookingCubit, CreateBookingState>(
      builder: (context, state) {
        return GlassTextField(
          controller: controller,
          label: 'event',
          hintText: 'optional',
          textCapitalization: TextCapitalization.sentences,
          onChanged: (input) =>
              context.read<CreateBookingCubit>().updateName(input),
        );
      },
    );
  }
}

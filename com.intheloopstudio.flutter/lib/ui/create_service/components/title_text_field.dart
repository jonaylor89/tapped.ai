import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/create_service/create_service_cubit.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class TitleTextField extends StatelessWidget {
  const TitleTextField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateServiceCubit, CreateServiceState>(
      builder: (context, state) {
        return GlassTextField(
          label: 'title',
          hintText: 'e.g. 2 hour DJ set',
          initialValue: state.title.value,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 56,
          onChanged: (input) =>
              context.read<CreateServiceCubit>().onTitleChange(
                input.trim(),
              ),
        );
      },
    );
  }
}

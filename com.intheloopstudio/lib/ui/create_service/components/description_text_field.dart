import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/create_service/create_service_cubit.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class DescriptionTextField extends StatelessWidget {
  const DescriptionTextField({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateServiceCubit, CreateServiceState>(
      builder: (context, state) {
        return GlassTextField(
          hintText: 'what does this service include?',
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          maxLines: null,
          maxLength: 1024,
          minLines: 6,
          initialValue: state.description.value,
          validator: (value) =>
              value!.isEmpty ? 'Description cannot be empty' : null,
          onChanged: (input) =>
              context.read<CreateServiceCubit>().onDescriptionChange(
                input.trim(),
              ),
        );
      },
    );
  }
}

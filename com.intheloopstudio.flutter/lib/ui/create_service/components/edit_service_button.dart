import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/ui/create_service/create_service_cubit.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class EditServiceButton extends StatelessWidget {
  const EditServiceButton({
    required this.onEdited,
    required this.service,
    this.label = 'save',
    super.key,
  });

  final String label;
  final void Function(Service) onEdited;
  final Service service;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateServiceCubit, CreateServiceState>(
      builder: (context, state) {
        return GlassButton.primary(
          label: label,
          expand: true,
          onPressed: () async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            try {
              await context.read<CreateServiceCubit>().edit(
                service,
                onEdited,
              );
            } catch (e) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: TappedColors.error,
                  content: Text(e.toString()),
                ),
              );
            }
          },
        );
      },
    );
  }
}

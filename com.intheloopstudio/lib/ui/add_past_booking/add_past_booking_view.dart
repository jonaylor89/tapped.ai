import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/data/storage_repository.dart';
import 'package:intheloopapp/domains/onboarding_bloc/onboarding_bloc.dart';
import 'package:intheloopapp/ui/add_past_booking/add_past_booking_cubit.dart';

import 'package:intheloopapp/ui/add_past_booking/components/import_form.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class AddPastBookingView extends StatelessWidget {
  const AddPastBookingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final database = context.read<DatabaseRepository>();
    final storage = context.read<StorageRepository>();
    final onboardingBloc = context.read<OnboardingBloc>();
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return BlocProvider(
          create: (context) => AddPastBookingCubit(
            onboardingBloc: onboardingBloc,
            storage: storage,
            database: database,
            currentUserId: currentUser.id,
          ),
          child: Scaffold(
            backgroundColor: theme.colorScheme.surface,
            body: const ImportForm(),
          ),
        );
      },
    );
  }
}

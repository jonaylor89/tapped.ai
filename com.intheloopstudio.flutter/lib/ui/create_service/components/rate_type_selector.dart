import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/ui/create_service/create_service_cubit.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class RateTypeSelector extends StatelessWidget {
  const RateTypeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateServiceCubit, CreateServiceState>(
      builder: (context, state) {
        return GlassSegmentedControl<RateType>(
          segments: const {
            RateType.hourly: GlassSegment(
              label: 'hourly',
              icon: CupertinoIcons.clock,
            ),
            RateType.fixed: GlassSegment(
              label: 'fixed',
              icon: CupertinoIcons.money_dollar,
            ),
          },
          selected: state.rateType,
          onChanged: context.read<CreateServiceCubit>().onRateTypeChange,
        );
      },
    );
  }
}

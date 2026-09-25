import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/common/opportunities_list.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';

class OpportunitiesSliver extends StatelessWidget {
  const OpportunitiesSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state.opportunities.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlassSectionTitle('apply to perform'),
            OpportunitiesList(
              opportunities: state.opportunities,
            ),
          ],
        );
      },
    );
  }
}

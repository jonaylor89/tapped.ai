import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/ui/settings/components/services_list.dart';

class ServicesSliver extends StatelessWidget {
  const ServicesSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final isCurrentUser = state.currentUser.id == state.visitedUser.id;
        if (state.services.isEmpty && !isCurrentUser) {
          return const SizedBox.shrink();
        }

        void createService() {
          context.push(
            CreateServicePage(
              onSubmit: context.read<ProfileCubit>().onServiceCreated,
              service: const None(),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassSectionTitle(
              'services',
              trailing: isCurrentUser
                  ? GlassIconButton(
                      icon: CupertinoIcons.add,
                      size: 36,
                      semanticsLabel: 'add service',
                      onPressed: createService,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
              ),
              child: ServicesList(
                services: state.services,
                isCurrentUser: isCurrentUser,
              ),
            ),
            const SizedBox(height: TappedSpacing.sm),
          ],
        );
      },
    );
  }
}

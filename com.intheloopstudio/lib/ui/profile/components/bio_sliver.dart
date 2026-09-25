import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:readmore/readmore.dart';

class BioSliver extends StatelessWidget {
  const BioSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        final bio = state.visitedUser.bio;
        if (bio.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GlassSectionTitle('about'),
            GlassCard(
              margin: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
              ),
              child: ReadMoreText(
                bio,
                colorClickableText: theme.colorScheme.primary,
                trimMode: TrimMode.Line,
                trimLines: 4,
                trimCollapsedText: ' more',
                trimExpandedText: ' less',
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
          ],
        );
      },
    );
  }
}

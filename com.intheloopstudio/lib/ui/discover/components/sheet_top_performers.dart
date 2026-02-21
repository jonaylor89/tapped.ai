import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/tapped_section_header.dart';
import 'package:intheloopapp/ui/discover/components/user_slider.dart';

class SheetTopPerformers extends StatelessWidget {
  const SheetTopPerformers({
    required this.performers,
    required this.isPremium,
    super.key,
  });

  final List<UserModel> performers;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    if (performers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TappedSectionHeader('top performers in area'),
        UserSlider(
          users: performers,
          sort: true,
          blur: !isPremium,
          onTap: isPremium ? null : () => context.push(PaywallPage()),
        ),
      ],
    );
  }
}

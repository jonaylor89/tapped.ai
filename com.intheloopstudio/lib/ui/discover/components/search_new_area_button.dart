import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/discover/discover_cubit.dart';

class SearchNewAreaButton extends StatelessWidget {
  const SearchNewAreaButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoverCubit, DiscoverState>(
      buildWhen: (a, b) => a.resultsExpired != b.resultsExpired,
      builder: (context, state) {
        return AnimatedSwitcher(
          duration: GlassMotion.reveal,
          switchInCurve: GlassMotion.spring,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: !state.resultsExpired
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: TappedSpacing.sm),
                  child: GlassButton(
                    label: 'search this area',
                    icon: CupertinoIcons.arrow_clockwise,
                    compact: true,
                    onPressed: context.read<DiscoverCubit>().searchNewBounds,
                  ),
                ),
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/ui/share_profile/share_profile_view.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class ShareButton extends StatelessWidget {
  const ShareButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return GlassButton.primary(
          label: 'share',
          icon: CupertinoIcons.square_arrow_up,
          expand: true,
          onPressed: () => showCupertinoModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) => ShareProfileView(
              userId: state.visitedUser.id,
              user: Option.of(state.visitedUser),
            ),
          ),
        );
      },
    );
  }
}

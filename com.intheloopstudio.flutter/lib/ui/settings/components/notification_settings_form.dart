import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/components/settings_switch.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';

class NotificationSettingsForm extends StatelessWidget {
  const NotificationSettingsForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        return Column(
          children: [
            GlassSection(
              header: 'push notifications',
              children: [
                SettingsSwitch(
                  icon: CupertinoIcons.bubble_left_fill,
                  iconColor: Colors.green,
                  label: 'new direct messages',
                  activated: state.pushNotificationsDirectMessages,
                  onChanged: (selected) =>
                      cubit.changeDirectMsgPush(selected: selected),
                ),
              ],
            ),
            GlassSection(
              header: 'emails',
              children: [
                SettingsSwitch(
                  icon: CupertinoIcons.sparkles,
                  iconColor: Colors.purple,
                  label: 'new app releases',
                  activated: state.emailNotificationsAppReleases,
                  onChanged: (selected) =>
                      cubit.changeAppReleaseEmail(selected: selected),
                ),
                SettingsSwitch(
                  icon: CupertinoIcons.envelope_fill,
                  iconColor: Colors.blue,
                  label: 'new direct messages',
                  activated: state.emailNotificationsDirectMessages,
                  onChanged: (selected) =>
                      cubit.changeDirectMessagesEmail(selected: selected),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:url_launcher/url_launcher.dart';

class ClaimProfileButton extends StatelessWidget {
  const ClaimProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBanner(
      icon: CupertinoIcons.person_badge_plus,
      title: 'is this you?',
      message: 'claim this profile to manage your bookings and details',
      actionLabel: 'claim',
      onAction: () {
        final uri = Uri.parse(
          'https://tappedapp.notion.site/claim-profile-9300a22781ed43dbba7cf53a17586b1d?pvs=4',
        );
        launchUrl(uri);
      },
    );
  }
}

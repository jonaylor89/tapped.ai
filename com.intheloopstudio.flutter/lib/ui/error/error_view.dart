import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key});

  void _logout(BuildContext context) {
    try {
      context.authentication.add(LoggedOut());
    } catch (e, s) {
      logger.error(
        'error logging out',
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'something went wrong',
      largeTitle: false,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassEmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'an error has occurred :/',
                message: 'try logging out and logging back in',
                actionLabel: 'log out',
                onAction: () => _logout(context),
              ),
              const SizedBox(height: TappedSpacing.xl),
              GlassSection(
                header: "if that doesn't work",
                children: [
                  GlassListTile(
                    leadingIcon: CupertinoIcons.envelope,
                    title: 'email support',
                    subtitle: 'support@tapped.ai',
                    onTap: () =>
                        launchUrl(Uri.parse('mailto:support@tapped.ai')),
                  ),
                  GlassListTile(
                    leadingIcon: CupertinoIcons.chat_bubble_2,
                    title: 'DM us on instagram',
                    subtitle: '@tappedai',
                    onTap: () => launchUrl(
                      Uri.parse('https://instagram.com/tappedai'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

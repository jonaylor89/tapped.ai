import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intheloopapp/domains/authentication_bloc/authentication_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/domains/subscription_bloc/subscription_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/components/settings_button.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/premium_builder.dart';
import 'package:url_launcher/url_launcher.dart';

class ActionMenu extends StatelessWidget {
  const ActionMenu({super.key});

  String? encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  void _showVerifiedSheet(BuildContext context) {
    final theme = Theme.of(context);
    showGlassSheet<void>(
      context: context,
      title: 'get verified',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.checkmark_seal_fill,
            color: theme.colorScheme.primary,
            size: 72,
          ),
          const SizedBox(height: TappedSpacing.lg),
          const GlassBanner(
            icon: CupertinoIcons.lightbulb_fill,
            title: 'how it works',
            message:
                'post a screenshot of your profile to your instagram story '
                'and tag us @tappedai',
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final nav = context.nav;
    final authBloc = context.authentication;
    final confirmed = await showGlassConfirm(
      context: context,
      title: 'sign out?',
      message: "you'll need to sign back in to see your bookings",
      confirmLabel: 'sign out',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      nav.popUntilHome();
      authBloc.add(LoggedOut());
    } catch (e, s) {
      logger.e('error signing out', error: e, stackTrace: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = context.subscriptions;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        return Column(
          children: [
            GlassSection(
              header: 'tapped premium',
              children: [
                PremiumBuilder(
                  builder: (context, isPremium) {
                    if (!isPremium) {
                      return SettingsButton(
                        icon: CupertinoIcons.star_fill,
                        iconColor: Colors.amber.shade700,
                        label: 'go premium',
                        onTap: () => context.push(PaywallPage()),
                      );
                    }
                    return SettingsButton(
                      icon: CupertinoIcons.star_fill,
                      iconColor: Colors.amber.shade700,
                      label: 'manage subscription',
                      onTap: () {
                        logger.debug('manage subscription');
                        return switch (subscriptions.state) {
                          Initialized(:final customerInfo) =>
                            customerInfo.managementURL != null
                                ? launchUrl(
                                    Uri.parse(customerInfo.managementURL!),
                                  )
                                : context.push(PaywallPage()),
                          _ => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red,
                                content: Text(
                                  'subscription is uninitialized',
                                ),
                              ),
                            ),
                        };
                      },
                    );
                  },
                ),
                SettingsButton(
                  icon: CupertinoIcons.checkmark_seal_fill,
                  iconColor: Colors.blue,
                  label: 'get verified',
                  onTap: () => _showVerifiedSheet(context),
                ),
              ],
            ),
            GlassSection(
              header: 'support',
              children: [
                SettingsButton(
                  icon: CupertinoIcons.chat_bubble_2_fill,
                  iconColor: Colors.green,
                  label: 'give us feedback',
                  onTap: () => launchUrl(
                    Uri(
                      scheme: 'mailto',
                      path: 'support@tapped.ai',
                      query: encodeQueryParameters(<String, String>{
                        'subject': 'Tapped User Feedback',
                      }),
                    ),
                  ),
                ),
                SettingsButton(
                  icon: CupertinoIcons.camera_fill,
                  iconColor: Colors.pink,
                  label: 'follow us on instagram',
                  onTap: () => launchUrl(
                    Uri(scheme: 'https', path: 'instagram.com/tappedai'),
                  ),
                ),
              ],
            ),
            GlassSection(
              header: 'legal',
              children: [
                SettingsButton(
                  icon: CupertinoIcons.hand_raised_fill,
                  iconColor: Colors.grey.shade600,
                  label: 'privacy policy',
                  onTap: () => launchUrl(
                    Uri(scheme: 'https', path: 'app.tapped.ai/privacy'),
                  ),
                ),
                SettingsButton(
                  icon: CupertinoIcons.doc_text_fill,
                  iconColor: Colors.grey.shade600,
                  label: 'terms of service',
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                    ),
                  ),
                ),
              ],
            ),
            GlassSection(
              children: [
                SettingsButton(
                  icon: CupertinoIcons.square_arrow_right,
                  iconColor: Colors.redAccent,
                  label: 'sign out',
                  destructive: true,
                  onTap: () => _signOut(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

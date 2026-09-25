import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class WaitlistView extends StatefulWidget {
  const WaitlistView({super.key});

  @override
  State<WaitlistView> createState() => _WaitlistViewState();
}

class _WaitlistViewState extends State<WaitlistView> {
  bool _loading = false;
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  static const _perks = [
    (CupertinoIcons.infinite, 'unlimited gig opportunities'),
    (CupertinoIcons.eye, 'exclusive info on venues looking for performers'),
    (CupertinoIcons.phone, 'contact info for thousands of venues'),
    (CupertinoIcons.slider_horizontal_3, 'advanced search'),
  ];

  Widget _hero(BuildContext context, {required String title}) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/splash.gif'),
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1],
                colors: [
                  Colors.transparent,
                  theme.colorScheme.surface,
                ],
              ),
            ),
          ),
          Positioned(
            left: GlassMetrics.edgeInset + TappedSpacing.xs,
            right: GlassMetrics.edgeInset + TappedSpacing.xs,
            bottom: 0,
            child: Text(
              title,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perkList(BuildContext context, {int count = 4}) {
    return GlassSection(
      children: [
        for (final (icon, text) in _perks.take(count))
          GlassListTile(
            leadingIcon: icon,
            leadingColor: TappedColors.success,
            title: text,
            showChevron: false,
          ),
      ],
    );
  }

  Widget _screen(
    BuildContext context, {
    required String title,
    required String caption,
    required int perkCount,
    required Widget bottomBar,
  }) {
    final theme = Theme.of(context);
    return GlassAmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(
                bottom: GlassMetrics.bottomBarClearance + 60,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                _hero(context, title: title),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GlassMetrics.edgeInset + TappedSpacing.xs,
                    TappedSpacing.sm,
                    GlassMetrics.edgeInset + TappedSpacing.xs,
                    TappedSpacing.md,
                  ),
                  child: Text(
                    caption,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ),
                _perkList(context, count: perkCount),
              ],
            ),
            const GlassNavChrome(backIcon: CupertinoIcons.xmark),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassBottomBar(
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  child: bottomBar,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadySignedUp(BuildContext context) {
    return _screen(
      context,
      title: "you're on\nthe waitlist",
      caption:
          "we'll let you know when premium is available. here's what "
          "you'll get:",
      perkCount: 4,
      bottomBar: GlassButton.primary(
        label: 'okay',
        expand: true,
        onPressed: () {
          HapticFeedback.lightImpact();
          _confettiController.play();
          context.popUntilHome();
        },
      ),
    );
  }

  Widget _buildWaitlist(
    BuildContext context, {
    required UserModel currentUser,
  }) {
    final database = context.database;
    final nav = context.nav;

    return _screen(
      context,
      title: 'get tapped\npremium',
      caption:
          "join the waitlist and we'll let you know when premium is "
          'available',
      perkCount: 3,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassButton.primary(
            label: 'join waitlist',
            icon: CupertinoIcons.sparkles,
            expand: true,
            isLoading: _loading,
            onPressed: () async {
              _confettiController.play();
              setState(() {
                _loading = true;
              });

              await database.joinPremiumWaitlist(currentUser.id);
              nav.popUntilHome();
              if (!mounted) return;
              setState(() {
                _loading = false;
              });
            },
          ),
          const SizedBox(height: TappedSpacing.xs),
          GlassButton.plain(
            label: 'not now',
            compact: true,
            onPressed: nav.pop,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = context.database;

    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return FutureBuilder(
          future: database.isOnPremiumWailist(currentUser.id),
          builder: (context, snapshot) {
            final isOnWaitlist = snapshot.data;

            return switch (isOnWaitlist) {
              null => const GlassAmbientBackground(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: GlassLoading(),
                ),
              ),
              false => _buildWaitlist(context, currentUser: currentUser),
              true => _buildAlreadySignedUp(context),
            };
          },
        );
      },
    );
  }
}

import 'package:avatar_stack/avatar_stack.dart';
import 'package:avatar_stack/positions.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/common/social_following_menu.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/request_to_perform/components/past_bookings_slider.dart';
import 'package:intheloopapp/ui/safety_mode_cubit.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class RequestToPerformView extends StatefulWidget {
  const RequestToPerformView({
    required this.venues,
    required this.collaborators,
    super.key,
  });

  final List<UserModel> venues;
  final List<UserModel> collaborators;

  @override
  State<RequestToPerformView> createState() => _RequestToPerformViewState();
}

class _RequestToPerformViewState extends State<RequestToPerformView> {
  String _note = '';
  List<UserModel> _collaborators = [];

  List<UserModel> get _venues => widget.venues;

  @override
  void initState() {
    super.initState();
    _collaborators = List.from(widget.collaborators);
  }

  Future<void> _send(
    BuildContext context, {
    required UserModel currentUser,
    required bool safeModeOn,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final nav = context.nav;

    if (_venues.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('no venues selected'),
        ),
      );
      return;
    }

    if (_note.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('message cannot be empty'),
        ),
      );
      return;
    }

    await EasyLoading.show(status: 'sending request');
    if (safeModeOn) {
      await Future<void>.delayed(const Duration(seconds: 1));
      await EasyLoading.dismiss();
      nav.push(RequestToPerformConfirmationPage(venues: _venues));
      return;
    }

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('genericContactVenues');
      await callable<void>({
        'userId': currentUser.id,
        'venueIds': _venues.map((venue) => venue.id).toList(),
        'note': _note,
        'collaborators': _collaborators.map((collaborator) {
          return collaborator.id;
        }).toList(),
      });
      await EasyLoading.dismiss();
      nav.push(RequestToPerformConfirmationPage(venues: _venues));
    } catch (error, stackTrace) {
      await EasyLoading.dismiss();
      logger.error(
        'error sending the request',
        error: error,
        stackTrace: stackTrace,
      );
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('error sending the request'),
        ),
      );
    }
  }

  Widget _buildSendButton(
    BuildContext context, {
    required UserModel currentUser,
  }) {
    return BlocBuilder<SafetyModeCubit, bool>(
      builder: (context, safeModeOn) {
        return GlassButton.primary(
          label: safeModeOn ? 'send request (safe mode on)' : 'send request',
          icon: CupertinoIcons.paperplane_fill,
          expand: true,
          onPressed: _note.isEmpty
              ? null
              : () => _send(
                  context,
                  currentUser: currentUser,
                  safeModeOn: safeModeOn,
                ),
        );
      },
    );
  }

  void _showPreview(BuildContext context, UserModel currentUser) {
    showGlassSheet<void>(
      context: context,
      title: 'what venues will see',
      scrollable: true,
      showClose: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GlassMetrics.edgeInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    imageUrl: currentUser.profilePicture,
                    radius: 24,
                  ),
                  const SizedBox(width: TappedSpacing.md),
                  Expanded(
                    child: Text(
                      currentUser.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TappedSpacing.lg),
              const GlassSectionTitle(
                'socials',
                padding: EdgeInsets.only(bottom: TappedSpacing.sm),
              ),
              SocialFollowingMenu(user: currentUser),
              const SizedBox(height: TappedSpacing.lg),
              const GlassSectionTitle(
                'booking history',
                padding: EdgeInsets.only(bottom: TappedSpacing.sm),
              ),
              PastBookingsSlider(user: currentUser),
              const SizedBox(height: TappedSpacing.xl),
            ],
          ),
        );
      },
    );
  }

  Widget _venueStack(ThemeData theme) {
    return SizedBox(
      height: 56,
      child: WidgetStack(
        positions: RestrictedPositions(
          infoItem: const InfoItem(indent: 5),
        ),
        stackedWidgets: _venues
            .map(
              (venue) => UserAvatar(
                pushUser: Option.of(venue),
                pushId: Option.of(venue.id),
                imageUrl: venue.profilePicture,
                radius: 28,
              ),
            )
            .toList(),
        buildInfoWidget: (surplus, context) {
          return LiquidGlass.circle(
            width: 56,
            height: 56,
            child: Center(
              child: Text(
                '+$surplus',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final venueLabel = switch (_venues.length) {
          0 => 'no venues selected',
          1 => _venues.first.displayName,
          final n => '$n venues',
        };
        return GlassPage(
          title: 'request to perform',
          subtitle: venueLabel,
          actions: [
            GlassIconButton(
              icon: CupertinoIcons.info,
              semanticsLabel: 'preview what venues will see',
              onPressed: () => _showPreview(context, currentUser),
            ),
          ],
          bottomBar: GlassBottomBar(
            child: _buildSendButton(context, currentUser: currentUser),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassMetrics.edgeInset,
                  vertical: TappedSpacing.md,
                ),
                child: Row(
                  children: [
                    _venueStack(theme),
                    const SizedBox(width: TappedSpacing.md),
                    Expanded(
                      child: Text(
                        'these venues will get your pitch, your socials, '
                        'and your booking history.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassMetrics.edgeInset,
                  vertical: TappedSpacing.sm,
                ),
                child: GlassCard(
                  child: TextFormField(
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    decoration: InputDecoration.collapsed(
                      hintText: 'what else should the venue know about you?',
                      hintStyle: TextStyle(color: muted),
                    ),
                    textInputAction: TextInputAction.done,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      letterSpacing: 0,
                      height: 1.4,
                    ),
                    maxLength: 512,
                    minLines: 8,
                    initialValue: _note,
                    validator: (value) =>
                        value!.isEmpty ? 'message cannot be empty' : null,
                    onChanged: (input) {
                      setState(() {
                        _note = input;
                      });
                    },
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GlassSection(
                header: 'collaborators',
                footer:
                    "you're far more likely to get booked when you're "
                    'on a bill with a local act.',
                children: [
                  for (final collaborator in _collaborators)
                    GlassListTile(
                      leading: UserAvatar(
                        pushId: Option.of(collaborator.id),
                        pushUser: Option.of(collaborator),
                        imageUrl: collaborator.profilePicture,
                        radius: 18,
                      ),
                      title: collaborator.displayName,
                      subtitle: '@${collaborator.username}',
                      showChevron: false,
                      trailing: GlassIconButton(
                        icon: CupertinoIcons.xmark,
                        size: 32,
                        iconSize: 14,
                        semanticsLabel: 'remove ${collaborator.displayName}',
                        onPressed: () {
                          setState(() {
                            _collaborators.remove(collaborator);
                          });
                        },
                      ),
                    ),
                  GlassListTile(
                    leadingIcon: CupertinoIcons.person_add_solid,
                    leadingColor: theme.colorScheme.primary,
                    titleWidget: Text(
                      'add collaborators',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      context.push(
                        AddCollaboratorsPage(
                          initialCollaborators: _collaborators,
                          onCollaboratorAdded: (collaborator) {
                            setState(() {
                              _collaborators.add(collaborator);
                            });
                          },
                          onCollaboratorRemoved: (collaborator) {
                            setState(() {
                              _collaborators.remove(collaborator);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: GlassMetrics.bottomBarClearance),
            ),
          ],
        );
      },
    );
  }
}

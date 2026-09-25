import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/common/performer_search_bar.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/user_avatar.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

class AddCollaboratorsView extends StatefulWidget {
  const AddCollaboratorsView({
    super.key,
    this.maxCollaborators = 5,
    this.onCollaboratorAdded,
    this.onCollaboratorRemoved,
    this.initialCollaborators = const [],
  });

  final int maxCollaborators;
  final void Function(UserModel)? onCollaboratorAdded;
  final void Function(UserModel)? onCollaboratorRemoved;
  final List<UserModel> initialCollaborators;

  @override
  State<AddCollaboratorsView> createState() => _AddCollaboratorsViewState();
}

class _AddCollaboratorsViewState extends State<AddCollaboratorsView> {
  var _collaborators = <UserModel>[];
  int get _maxCollaborators => widget.maxCollaborators;

  @override
  void initState() {
    super.initState();
    _collaborators = List.from(widget.initialCollaborators);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atMax = _collaborators.length >= _maxCollaborators;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return GlassPage(
          title: 'build a bill',
          subtitle: "you're more likely to get gigs on a larger bill",
          bottomBar: GlassBottomBar(
            child: GlassButton.primary(
              label: 'done',
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassMetrics.edgeInset,
                  vertical: TappedSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PerformerSearchBar(
                      onSelected: (user) {
                        if (_collaborators.length >= _maxCollaborators) {
                          return;
                        }

                        if (user.id == currentUser.id) {
                          return;
                        }

                        if (_collaborators.contains(user)) {
                          return;
                        }

                        widget.onCollaboratorAdded?.call(user);
                        setState(() {
                          _collaborators.add(user);
                        });
                      },
                    ),
                    if (atMax)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: TappedSpacing.sm,
                          left: TappedSpacing.sm,
                        ),
                        child: Text(
                          'you can add up to $_maxCollaborators collaborators',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: TappedColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: GlassSection(
                header: 'bill · ${_collaborators.length}/$_maxCollaborators',
                children: [
                  if (_collaborators.isEmpty)
                    const GlassEmptyState(
                      icon: CupertinoIcons.person_2,
                      title: 'no one yet',
                      message: 'search for performers to add to the bill',
                      compact: true,
                    ),
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
                          widget.onCollaboratorRemoved?.call(collaborator);
                          setState(() {
                            _collaborators.remove(collaborator);
                          });
                        },
                      ),
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

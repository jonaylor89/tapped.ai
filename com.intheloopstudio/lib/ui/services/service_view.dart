import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/error/error_view.dart';
import 'package:intheloopapp/ui/profile/components/request_to_book.dart';
import 'package:intheloopapp/ui/user_tile.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';

/// Service detail: price-forward glass card, description, and either the
/// owner's edit/delete controls or a request-to-book action.
class ServiceView extends StatelessWidget {
  const ServiceView({
    required this.service,
    required this.serviceUser,
    super.key,
  });

  final Service service;
  final Option<UserModel> serviceUser;

  String get _price =>
      '\$${(service.rate / 100).toStringAsFixed(2)}'
      '${service.rateType == RateType.hourly ? '/hr' : ''}';

  void _edit(BuildContext context) {
    context
      ..pop()
      ..push(
        CreateServicePage(
          onSubmit: (Service service) {},
          service: Option.of(service),
        ),
      );
  }

  Future<void> _delete(BuildContext context) async {
    final database = context.database;
    final confirmed = await showGlassConfirm(
      context: context,
      title: 'delete this service?',
      message: 'people will no longer be able to book "${service.title}".',
      confirmLabel: 'delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.pop();
    await database.deleteService(service.userId, service.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final database = context.database;
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final isOwner = currentUser.id == service.userId;
        return GlassPage(
          title: 'service',
          largeTitle: false,
          actions: [
            if (isOwner)
              GlassIconButton(
                icon: CupertinoIcons.pencil,
                semanticsLabel: 'edit service',
                onPressed: () => _edit(context),
              ),
          ],
          bottomBar: GlassBottomBar(
            child: isOwner
                ? GlassButton.destructive(
                    label: 'delete service',
                    icon: CupertinoIcons.trash,
                    expand: true,
                    onPressed: () => _delete(context),
                  )
                : FutureBuilder<Option<UserModel>>(
                    future: database.getUserById(service.userId),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      return switch (data) {
                        null => const GlassLoading(),
                        None() => const ErrorView(),
                        Some(:final value) => RequestToBookButton(user: value),
                      };
                    },
                  ),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
              ),
              sliver: SliverList.list(
                children: [
                  GlassCard(
                    tint: TappedColors.success,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: TappedSpacing.md),
                        Text(
                          _price,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: TappedColors.success,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          service.rateType == RateType.hourly
                              ? 'hourly rate'
                              : 'flat rate',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (service.description.trim().isNotEmpty) ...[
                    const GlassSectionTitle(
                      'about',
                      padding: EdgeInsets.only(
                        top: TappedSpacing.xl,
                        bottom: TappedSpacing.sm,
                      ),
                    ),
                    Text(
                      service.description,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ],
                ],
              ),
            ),
            const SliverToBoxAdapter(child: GlassSectionTitle('offered by')),
            SliverToBoxAdapter(
              child: GlassSection(
                children: [
                  UserTile(userId: service.userId, user: serviceUser),
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

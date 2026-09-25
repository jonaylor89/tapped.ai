import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/conditional_parent_widget.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/profile_cubit.dart';
import 'package:intheloopapp/ui/settings/components/service_card.dart';
import 'package:intheloopapp/utils/admin_builder.dart';

class ServicesList extends StatelessWidget {
  const ServicesList({
    required this.services,
    required this.isCurrentUser,
    super.key,
  });

  final List<Service> services;
  final bool isCurrentUser;

  Widget _customBookingButton(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return SizedBox(
          width: 190,
          child: GlassCard(
            semanticsLabel: 'custom booking',
            tint: theme.colorScheme.primary,
            padding: const EdgeInsets.all(TappedSpacing.lg),
            onTap: () => context.push(
              CreateBookingPage(
                requesteeId: state.visitedUser.id,
                service: const None(),
                requesteeStripeConnectedAccountId:
                    state.visitedUser.stripeConnectedAccountId,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.pencil_outline,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  'custom booking',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: TappedSpacing.xs),
                Text(
                  'name your own terms',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminBuilder(
      builder: (context, isAdmin) {
        return Column(
          children: [
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: GlassMetrics.edgeInset,
                ),
                physics: const BouncingScrollPhysics(),
                separatorBuilder: (_, __) =>
                    const SizedBox(width: TappedSpacing.md),
                itemCount: isCurrentUser
                    ? services.length
                    : services.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0 && !isCurrentUser) {
                    return _customBookingButton(context);
                  }

                  final listIndex = isCurrentUser ? index : index - 1;
                  final service = services[listIndex];
                  return ConditionalParentWidget(
                    condition: isCurrentUser || isAdmin,
                    conditionalBuilder:
                        ({
                          required Widget child,
                        }) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              child,
                              Positioned(
                                top: TappedSpacing.sm,
                                right: TappedSpacing.sm,
                                child: GlassIconButton(
                                  icon: CupertinoIcons.pencil,
                                  size: 34,
                                  semanticsLabel: 'edit service',
                                  onPressed: () {
                                    try {
                                      context.push(
                                        CreateServicePage(
                                          onSubmit: context
                                              .read<ProfileCubit>()
                                              .onServiceEdited,
                                          service: Option.of(service),
                                        ),
                                      );
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: TappedColors.error,
                                          content: Text(
                                            'Error editing service',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                    child: ServiceCard(
                      service: service,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

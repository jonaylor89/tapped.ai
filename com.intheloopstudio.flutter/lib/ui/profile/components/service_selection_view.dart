import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class ServiceSelectionView extends StatelessWidget {
  const ServiceSelectionView({
    required this.userId,
    required this.requesteeStripeConnectedAccountId,
    super.key,
  });

  final String userId;
  final Option<String> requesteeStripeConnectedAccountId;

  void Function()? buildOnTap(BuildContext context, Service service) {
    return switch ((requesteeStripeConnectedAccountId, service.rate)) {
      (_, <= 0) => () => context.push(
        CreateBookingPage(
          requesteeId: userId,
          service: Option.of(service),
          requesteeStripeConnectedAccountId: const None(),
        ),
      ),
      (None(), _) => null,
      (Some(:final value), _) => () => context.push(
        CreateBookingPage(
          requesteeId: userId,
          service: Option.of(service),
          requesteeStripeConnectedAccountId: Option.of(value),
        ),
      ),
    };
  }

  String _price(Service service) {
    final amount = (service.rate / 100).toStringAsFixed(2);
    final suffix = service.rateType == RateType.hourly ? '/hr' : '';
    return '\$$amount$suffix';
  }

  Widget _buildListItem(BuildContext context, Service service) {
    final onTap = buildOnTap(context, service);
    final locked = onTap == null;
    return GlassListTile(
      leadingIcon: locked ? CupertinoIcons.lock_fill : CupertinoIcons.music_mic,
      leadingColor: locked ? Colors.grey : TappedColors.accent,
      title: service.title,
      subtitle: locked
          ? "artist's payment info isn't connected"
          : service.description,
      trailing: GlassPill(
        label: _price(service),
        tint: locked ? Colors.grey : TappedColors.success,
        foreground: TappedColors.textOnImage,
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'book',
      subtitle: 'pick a service',
      padding: EdgeInsets.zero,
      slivers: [
        SliverToBoxAdapter(
          child: FutureBuilder<List<Service>>(
            future: context.database.getUserServices(userId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(TappedSpacing.xxxl),
                  child: Center(child: GlassLoading()),
                );
              }

              final services = snapshot.data!;
              final sortedServices = services
                ..sort((a, b) => a.rate > b.rate ? 1 : -1);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassSection(
                    children: [
                      GlassListTile(
                        leadingIcon: CupertinoIcons.pencil_outline,
                        leadingColor: Theme.of(context).colorScheme.primary,
                        title: 'custom booking',
                        subtitle: 'name your own terms',
                        onTap: () => context.push(
                          CreateBookingPage(
                            requesteeId: userId,
                            service: const None(),
                            requesteeStripeConnectedAccountId:
                                requesteeStripeConnectedAccountId,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (services.isNotEmpty)
                    GlassSection(
                      header: 'services',
                      children: [
                        for (final service in sortedServices)
                          _buildListItem(context, service),
                      ],
                    ),
                  const SizedBox(height: TappedSpacing.xxl),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

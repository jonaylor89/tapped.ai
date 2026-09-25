import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    required this.service,
    super.key,
  });

  final Service service;

  String get _price {
    final amount = (service.rate / 100).toStringAsFixed(2);
    final suffix = service.rateType == RateType.hourly ? '/hr' : '';
    return '\$$amount$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 190,
      child: GlassCard(
        semanticsLabel: service.title,
        padding: const EdgeInsets.all(TappedSpacing.lg),
        onTap: () => context.push(
          ServicePage(
            service: service,
            serviceUser: const None(),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TappedColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.music_mic,
                size: 20,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Text(
              service.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: TappedSpacing.xs),
            Text(
              _price,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: TappedColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

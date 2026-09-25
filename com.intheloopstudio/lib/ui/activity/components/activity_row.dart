import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:timeago/timeago.dart' as timeago;

/// One notification: leading avatar/icon, bold-when-unread title and
/// message, relative timestamp, and an unread dot — inside a glass card so
/// the list reads as a stack of floating rows rather than a flat table.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    required this.leading,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.unread,
    this.onTap,
    super.key,
  });

  final Widget leading;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GlassMetrics.edgeInset,
        vertical: TappedSpacing.xs,
      ),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(TappedSpacing.md),
        tint: unread ? theme.colorScheme.primary : null,
        child: Row(
          children: [
            leading,
            const SizedBox(width: TappedSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: unread ? theme.colorScheme.onSurface : muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TappedSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeago.format(timestamp, locale: 'en_short'),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
                if (unread) ...[
                  const SizedBox(height: TappedSpacing.sm),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

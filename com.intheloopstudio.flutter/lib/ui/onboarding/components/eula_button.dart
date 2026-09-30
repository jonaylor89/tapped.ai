import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:url_launcher/url_launcher.dart';

class EULAButton extends StatelessWidget {
  const EULAButton({
    required this.onChanged,
    required this.initialValue,
    super.key,
  });

  final bool initialValue;
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSection(
      margin: EdgeInsets.zero,
      children: [
        GlassListTile(
          leading: GlassPressable(
            semanticsLabel: initialValue ? 'agreed to EULA' : 'agree to EULA',
            onPressed: () => onChanged(!initialValue),
            child: Icon(
              initialValue
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: initialValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
          titleWidget: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'EULA',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: TappedSpacing.xs),
                    child: Icon(
                      CupertinoIcons.arrow_up_right_square,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            style: theme.textTheme.bodyLarge,
          ),
          showChevron: false,
          onTap: () => onChanged(!initialValue),
          trailing: GlassButton.plain(
            label: 'read',
            compact: true,
            onPressed: () => launchUrl(Uri.parse('https://app.tapped.ai/eula')),
          ),
        ),
      ],
    );
  }
}

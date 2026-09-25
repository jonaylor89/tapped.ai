import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/settings/components/genre_selection.dart';
import 'package:intheloopapp/utils/premium_builder.dart';

/// Content of the discover "filters" sheet: genres and venue capacity.
class MapSettings extends StatefulWidget {
  const MapSettings({
    required this.genreFilters,
    required this.onConfirmGenreSelection,
    required this.onCapacityRangeChange,
    this.initialRange,
    this.maxCapacity = 1000,
    super.key,
  });

  final List<Genre> genreFilters;
  final void Function(List<Genre?>) onConfirmGenreSelection;
  final void Function(RangeValues) onCapacityRangeChange;
  final RangeValues? initialRange;

  final int maxCapacity;

  @override
  State<MapSettings> createState() => _MapSettingsState();
}

class _MapSettingsState extends State<MapSettings> {
  late RangeValues capacityRange;

  int get capacityRangeStart => capacityRange.start.round();

  int get capacityRangeEnd => capacityRange.end.round();

  @override
  void initState() {
    capacityRange =
        widget.initialRange ??
        RangeValues(
          0,
          widget.maxCapacity.toDouble(),
        );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumBuilder(
      builder: (context, isPremium) {
        if (!isPremium) {
          return GlassEmptyState(
            icon: CupertinoIcons.lock_fill,
            title: 'filters are premium',
            message:
                'narrow venues by genre and capacity to find '
                'the rooms that fit your act',
            actionLabel: 'upgrade',
            onAction: () => context.push(PaywallPage()),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassSection(
              margin: EdgeInsets.zero,
              children: [
                GenreSelection(
                  standalone: false,
                  initialValue: widget.genreFilters,
                  onConfirm: widget.onConfirmGenreSelection,
                ),
              ],
            ),
            GlassSectionTitle(
              'capacity',
              padding: const EdgeInsets.only(
                top: TappedSpacing.xl,
                bottom: TappedSpacing.sm,
              ),
              trailing: GlassPill(
                label:
                    '$capacityRangeStart – '
                    '${capacityRangeEnd == widget.maxCapacity ? '${widget.maxCapacity}+' : capacityRangeEnd}',
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                rangeThumbShape: const RoundRangeSliderThumbShape(
                  enabledThumbRadius: 13,
                  elevation: 2,
                ),
                thumbColor: Colors.white,
                overlayColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.12,
                ),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: RangeSlider(
                values: capacityRange,
                max: widget.maxCapacity.toDouble(),
                divisions: widget.maxCapacity ~/ 10,
                onChanged: (range) {
                  setState(() => capacityRange = range);
                },
                onChangeEnd: widget.onCapacityRangeChange,
              ),
            ),
          ],
        );
      },
    );
  }
}

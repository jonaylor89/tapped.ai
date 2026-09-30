import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/booking_history/booking_history_cubit.dart';
import 'package:intheloopapp/ui/booking_history/components/booking_bottom_sheet.dart';
import 'package:intheloopapp/ui/booking_history/components/booking_map.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';

class BookingHistoryView extends StatelessWidget {
  const BookingHistoryView({
    required this.user,
    super.key,
  });

  final UserModel user;

  Widget _buildControlButtons(
    BuildContext context,
    MapController mapController,
  ) {
    return BlocBuilder<BookingHistoryCubit, BookingHistoryState>(
      builder: (context, state) {
        return Positioned(
          bottom: MediaQuery.sizeOf(context).height * 0.12 + TappedSpacing.md,
          right: GlassMetrics.edgeInset,
          child: Column(
            children: [
              GlassIconButton(
                icon: state.showFlierMarkers
                    ? CupertinoIcons.photo_fill
                    : CupertinoIcons.photo,
                variant: GlassVariant.clear,
                semanticsLabel: 'toggle flier markers',
                onPressed: () {
                  FirebaseAnalytics.instance.logEvent(
                    name: 'toggle_flier_markers',
                  );

                  context.read<BookingHistoryCubit>().toggleFlierMarkers();
                },
              ),
              if (kDebugMode) ...[
                const SizedBox(height: TappedSpacing.sm),
                GlassIconButton(
                  icon: CupertinoIcons.plus,
                  variant: GlassVariant.clear,
                  semanticsLabel: 'zoom in',
                  onPressed: () {
                    mapController.move(
                      mapController.camera.center,
                      mapController.camera.zoom + 1,
                    );
                  },
                ),
                const SizedBox(height: TappedSpacing.sm),
                GlassIconButton(
                  icon: CupertinoIcons.minus,
                  variant: GlassVariant.clear,
                  semanticsLabel: 'zoom out',
                  onPressed: () {
                    mapController.move(
                      mapController.camera.center,
                      mapController.camera.zoom - 1,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapController = MapController();
    return BlocProvider(
      create: (context) => BookingHistoryCubit(
        database: context.database,
        userId: user.id,
      )..initBookings(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            BookingMap(mapController: mapController),
            _buildControlButtons(context, mapController),
            Positioned(
              top: MediaQuery.paddingOf(context).top + TappedSpacing.sm,
              left: GlassMetrics.edgeInset,
              right: GlassMetrics.edgeInset,
              child: Row(
                children: [
                  GlassIconButton(
                    icon: CupertinoIcons.chevron_back,
                    variant: GlassVariant.clear,
                    semanticsLabel: 'back',
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: TappedSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GlassPill(
                        label: '${user.displayName} · bookings',
                        variant: GlassVariant.clear,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomSheet: BookingBottomSheet(user: user),
      ),
    );
  }
}

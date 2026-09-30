import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/booking_card.dart';
import 'package:intheloopapp/ui/profile/components/booking_tile.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:rxdart/rxdart.dart';

class UserBookingsFeed extends StatefulWidget {
  const UserBookingsFeed({
    required this.userId,
    super.key,
  });

  final String userId;

  @override
  State<UserBookingsFeed> createState() => _UserBookingsFeedState();
}

class _UserBookingsFeedState extends State<UserBookingsFeed> {
  String get _userId => widget.userId;
  Timer? _debounce;
  final _scrollController = ScrollController();
  List<Booking> _userBookings = const [];
  bool _hasReachedMaxBookings = false;
  BookingsStatus _bookingsStatus = BookingsStatus.initial;
  StreamSubscription<Booking>? _bookingListener;
  late DatabaseRepository _databaseRepository;

  bool isList = false;

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    return currentScroll >= (maxScroll * 0.9);
  }

  Future<void> _initBookings({bool clearBookings = true}) async {
    final trace = logger.createTrace('initBookings');
    await trace.start();
    try {
      logger.debug(
        'initBookings $_userId',
      );
      await _bookingListener?.cancel();
      if (clearBookings) {
        setState(() {
          _bookingsStatus = BookingsStatus.initial;
          _userBookings = [];
          _hasReachedMaxBookings = false;
        });
      }

      setState(() {
        _bookingsStatus = BookingsStatus.success;
      });

      _bookingListener = Rx.merge([
        _databaseRepository.getBookingsByRequesteeObserver(
          _userId,
          status: BookingStatus.confirmed,
        ),
        _databaseRepository.getBookingsByRequesterObserver(
          _userId,
          status: BookingStatus.confirmed,
        ),
      ]).listen((Booking event) {
        logger.debug('booking { ${event.id} : ${event.name} }');
        try {
          setState(() {
            _bookingsStatus = BookingsStatus.success;
            _userBookings = List.of(_userBookings)..add(event);
            _hasReachedMaxBookings = _userBookings.length < 20;
          });
        } catch (e, s) {
          logger.error('initBookings error', error: e, stackTrace: s);
        }
      });
    } catch (e, s) {
      logger.error('initBookings error', error: e, stackTrace: s);
    } finally {
      await trace.stop();
    }
  }

  Future<void> _fetchMoreBookings() async {
    if (_hasReachedMaxBookings) return;

    final trace = logger.createTrace('fetchMoreBookings');
    await trace.start();
    try {
      if (_bookingsStatus == BookingsStatus.initial) {
        await _initBookings();
      }

      final bookingsRequestee =
          await _databaseRepository.getBookingsByRequestee(
        _userId,
        limit: 50,
        lastBookingRequestId:
            _userBookings.where((e) => e.requesteeId == _userId).lastOrNull?.id,
      );
      final bookingsRequester =
          await _databaseRepository.getBookingsByRequester(
        _userId,
        limit: 50,
        lastBookingRequestId: _userBookings
            .where((e) => e.requesterId.getOrElse(() => '') == _userId)
            .lastOrNull
            ?.id,
      );

      (bookingsRequestee.isEmpty && bookingsRequester.isEmpty)
          ? setState(() {
              _hasReachedMaxBookings = true;
            })
          : setState(() {
              _bookingsStatus = BookingsStatus.success;
              _userBookings = List.of(_userBookings)
                ..addAll(bookingsRequestee)
                ..addAll(bookingsRequester);
              _hasReachedMaxBookings = false;
            });
    } catch (e, s) {
      logger.error(
        'fetchMoreBookings error',
        error: e,
        stackTrace: s,
      );
      // emit(_copyWith(bookingsStatus: BookingsStatus.failure));
    } finally {
      await trace.stop();
    }
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_isBottom) _fetchMoreBookings();
    });
  }

  @override
  void initState() {
    super.initState();
    _databaseRepository = context.database;
    _scrollController.addListener(_onScroll);
    _initBookings();
  }

  Widget _buildUserBookingFeed(UserModel user) => switch (_bookingsStatus) {
        BookingsStatus.initial => const Center(child: GlassLoading()),
        BookingsStatus.failure => const GlassEmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'failed to fetch bookings',
          ),
        BookingsStatus.success => () {
            if (_userBookings.isEmpty || user.deleted) {
              return const GlassEmptyState(
                icon: CupertinoIcons.calendar,
                title: 'no bookings yet',
                message: 'confirmed gigs will show up here',
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: GlassMetrics.edgeInset,
                vertical: TappedSpacing.sm,
              ),
              sliver: isList
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return BookingTile(
                            visitedUser: user,
                            booking: _userBookings[index],
                          );
                        },
                        childCount: _userBookings.length,
                      ),
                    )
                  : SliverGrid.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: TappedSpacing.md,
                      mainAxisSpacing: TappedSpacing.md,
                      childAspectRatio: 0.78,
                      children: _userBookings.map((booking) {
                        return BookingCard(
                          visitedUser: user,
                          booking: booking,
                        );
                      }).toList(),
                    ),
            );
          }(),
      };

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        final isCurrentUser = currentUser.id == _userId;
        return FutureBuilder<Option<UserModel>>(
          future: _databaseRepository.getUserById(_userId),
          builder: (context, snapshot) {
            final user = snapshot.data;
            final body = switch (user) {
              null => const Center(child: GlassLoading()),
              None() => const GlassEmptyState(
                  icon: CupertinoIcons.person_crop_circle_badge_xmark,
                  title: 'user not found',
                ),
              Some(:final value) => _buildUserBookingFeed(value),
            };
            return GlassPage(
              title: 'bookings',
              subtitle: switch (user) {
                Some(:final value) => value.displayName,
                _ => null,
              },
              scrollController: _scrollController,
              onRefresh: _initBookings,
              actions: [
                GlassIconButton(
                  icon: isList
                      ? CupertinoIcons.square_grid_2x2
                      : CupertinoIcons.list_bullet,
                  semanticsLabel: isList ? 'show grid' : 'show list',
                  onPressed: () => setState(() => isList = !isList),
                ),
              ],
              bottomBar: isCurrentUser
                  ? GlassButton.primary(
                      label: 'add past booking',
                      icon: CupertinoIcons.add,
                      expand: true,
                      onPressed: () => context.push(AddPastBookingPage()),
                    )
                  : null,
              slivers: [
                if (body is SliverPadding)
                  body
                else
                  SliverFillRemaining(hasScrollBody: false, child: body),
                const SliverToBoxAdapter(
                  child: SizedBox(height: GlassMetrics.bottomBarClearance),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum BookingsStatus {
  initial,
  success,
  failure,
}

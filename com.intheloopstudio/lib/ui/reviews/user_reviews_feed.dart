import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/models/review.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/ui/design/app_tokens.dart';
import 'package:intheloopapp/ui/design/glass/glass.dart';
import 'package:intheloopapp/ui/profile/components/review_tile.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/bloc_utils.dart';
import 'package:rxdart/rxdart.dart';

class UserReviewsFeed extends StatefulWidget {
  const UserReviewsFeed({
    required this.userId,
    super.key,
  });

  final String userId;

  @override
  State<UserReviewsFeed> createState() => _UserReviewsFeedState();
}

class _UserReviewsFeedState extends State<UserReviewsFeed> {
  String get _userId => widget.userId;
  Timer? _debounce;
  final _scrollController = ScrollController();
  List<Review> _userReviews = const [];
  bool _hasReachedMaxReviews = false;
  ReviewsStatus _reviewsStatus = ReviewsStatus.initial;
  StreamSubscription<Review>? _bookingListener;
  late DatabaseRepository _databaseRepository;

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    return currentScroll >= (maxScroll * 0.9);
  }

  Future<void> _initReviews({bool clearReviews = true}) async {
    final trace = logger.createTrace('initReviews');
    await trace.start();
    try {
      logger.debug(
        'initReviews $_userId',
      );
      await _bookingListener?.cancel();
      if (clearReviews) {
        setState(() {
          _reviewsStatus = ReviewsStatus.initial;
          _userReviews = [];
          _hasReachedMaxReviews = false;
        });
      }

      setState(() {
        _reviewsStatus = ReviewsStatus.success;
      });

      _bookingListener =
          Rx.merge([
            _databaseRepository.getBookerReviewsByBookerIdObserver(
              _userId,
            ),
            _databaseRepository.getPerformerReviewsByPerformerIdObserver(
              _userId,
            ),
          ]).listen((Review event) {
            logger.debug('review { ${event.id} }');
            try {
              setState(() {
                _reviewsStatus = ReviewsStatus.success;
                _userReviews = List.of(_userReviews)..add(event);
                _hasReachedMaxReviews = _userReviews.length < 20;
              });
            } catch (e, s) {
              logger.error('initReviews error', error: e, stackTrace: s);
            }
          });
    } catch (e, s) {
      logger.error('initReviews error', error: e, stackTrace: s);
    } finally {
      await trace.stop();
    }
  }

  Future<void> _fetchMoreReviews() async {
    if (_hasReachedMaxReviews) return;

    final trace = logger.createTrace('fetchMoreReviews');
    await trace.start();
    try {
      if (_reviewsStatus == ReviewsStatus.initial) {
        await _initReviews();
      }

      final reviewsPerformer = await _databaseRepository
          .getPerformerReviewsByPerformerId(
            _userId,
            limit: 10,
            lastReviewId: _userReviews
                .where((e) => e.performerId == _userId)
                .last
                .id,
          );
      final reviewsBooker = await _databaseRepository
          .getBookerReviewsByBookerId(
            _userId,
            limit: 10,
            lastReviewId: _userReviews
                .where((e) => e.bookerId == _userId)
                .last
                .id,
          );

      (reviewsPerformer.isEmpty && reviewsBooker.isEmpty)
          ? setState(() {
              _hasReachedMaxReviews = true;
            })
          : setState(() {
              _reviewsStatus = ReviewsStatus.success;
              _userReviews = List.of(_userReviews)
                ..addAll(reviewsPerformer)
                ..addAll(reviewsBooker);
              _hasReachedMaxReviews = false;
            });
    } catch (e, s) {
      logger.error(
        'fetchMoreReviews error',
        error: e,
        stackTrace: s,
      );
      // emit(_copyWith(reviewsStatus: ReviewsStatus.failure));
    } finally {
      await trace.stop();
    }
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_isBottom) _fetchMoreReviews();
    });
  }

  @override
  void initState() {
    super.initState();
    _databaseRepository = context.database;
    _scrollController.addListener(_onScroll);
    _initReviews();
  }

  Widget _buildUserReviewFeed(UserModel user) {
    final empty = _userReviews.isEmpty || user.deleted;
    return GlassPage(
      title: 'reviews',
      subtitle: user.artistName,
      scrollController: _scrollController,
      onRefresh: _initReviews,
      slivers: [
        switch (_reviewsStatus) {
          ReviewsStatus.initial => const SliverFillRemaining(
            hasScrollBody: false,
            child: GlassLoading(),
          ),
          ReviewsStatus.failure => const SliverFillRemaining(
            hasScrollBody: false,
            child: GlassEmptyState(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'failed to fetch reviews',
              message: 'pull down to try again',
            ),
          ),
          ReviewsStatus.success when empty => const SliverFillRemaining(
            hasScrollBody: false,
            child: GlassEmptyState(
              icon: CupertinoIcons.star,
              title: 'no reviews yet',
              message: 'reviews show up here after completed bookings',
            ),
          ),
          ReviewsStatus.success => SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: GlassMetrics.edgeInset,
              vertical: TappedSpacing.sm,
            ),
            sliver: SliverList.separated(
              itemCount: _userReviews.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: TappedSpacing.sm),
              itemBuilder: (context, index) =>
                  ReviewTile(review: _userReviews[index]),
            ),
          ),
        },
        const SliverToBoxAdapter(
          child: SizedBox(height: TappedSpacing.xxxl),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _bookingListener?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Option<UserModel>>(
      future: _databaseRepository.getUserById(_userId),
      builder: (context, snapshot) {
        final user = snapshot.data;
        return switch (user) {
          null => const GlassPage(
            title: 'reviews',
            child: GlassLoading(),
          ),
          None() => const GlassPage(
            title: 'reviews',
            child: GlassEmptyState(
              icon: CupertinoIcons.person_crop_circle_badge_xmark,
              title: 'user not found',
            ),
          ),
          Some(:final value) => _buildUserReviewFeed(value),
        };
      },
    );
  }
}

enum ReviewsStatus {
  initial,
  success,
  failure,
}

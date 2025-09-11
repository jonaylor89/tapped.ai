import 'package:cached_annotation/cached_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:enum_to_string/enum_to_string.dart';
import 'package:feedback/feedback.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:fpdart/fpdart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:georange/georange.dart';
import 'package:intheloopapp/data/database_repository.dart';
import 'package:intheloopapp/domains/models/activity.dart';
import 'package:intheloopapp/domains/models/badge.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/performer_info.dart';
import 'package:intheloopapp/domains/models/review.dart';
import 'package:intheloopapp/domains/models/service.dart';
import 'package:intheloopapp/domains/models/social_following.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/categroize.dart';
import 'package:intheloopapp/utils/default_value.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rxdart/rxdart.dart';

// final _storage = FirebaseStorage.instance.ref();
final _firestore = FirebaseFirestore.instance;
final _analytics = FirebaseAnalytics.instance;

final _usersRef = _firestore.collection('users');
final _activitiesRef = _firestore.collection('activities');
final _badgesRef = _firestore.collection('badges');
final _badgesSentRef = _firestore.collection('badgesSent');
final _bookingsRef = _firestore.collection('bookings');
final _servicesRef = _firestore.collection('services');
final _mailRef = _firestore.collection('mail');
final _leadersRef = _firestore.collection('leaderboard');
final _blockerRef = _firestore.collection('blockers');
// final _blockeeRef = _firestore.collection('blockees');
final _reviewsRef = _firestore.collection('reviews');
final _opportunitiesRef = _firestore.collection('opportunities');
final _opportunityFeedsRef = _firestore.collection('opportunityFeeds');
final _creditsRef = _firestore.collection('credits');
final _premiumWailistRef = _firestore.collection('premiumWaitlist');
final _userFeedbackRef = _firestore.collection('userFeedback');
final _contactVenuesRef = _firestore.collection('contactVenues');

const verifiedBadgeId = '0aa46576-1fbe-4312-8b69-e2fef3269083';

const blockerSubcollection = 'blockedUsers';
const blockeeSubcollection = 'blockedByUsers';

const bookerReviewsSubcollection = 'bookerReviews';
const performerReviewsSubcollection = 'performerReviews';

const tccUserId = 'yfjw9oCMwPVzAxgENxGxecPcNym1';

Future<bool> _asyncShouldCache(bool candidate) async {
  return candidate;
}

/// Database implementation using Firebase's FirestoreDB
class FirestoreDatabaseImpl extends DatabaseRepository {
  String _getFileFromURL(String fileURL) {
    final fSlashes = fileURL.split('/');
    final fQuery = fSlashes[fSlashes.length - 1].split('?');
    final segments = fQuery[0].split('%2F');
    final fileName = segments.join('/');

    return fileName;
  }

  @override
  Future<String> publishLatestAppVersion(String currentUserId) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final buildNumber = packageInfo.buildNumber;
      final latestAppVersion = '$version+$buildNumber';

      await _usersRef.doc(currentUserId).set(
        {
          'latestAppVersion': latestAppVersion,
        },
        SetOptions(merge: true),
      );

      return latestAppVersion;
    } catch (e, s) {
      logger.error('publishLatestAppVersion', error: e, stackTrace: s);
      rethrow;
    }
  }

  // true if username available, false otherwise
  @override
  Future<bool> checkUsernameAvailability(
    String username,
    String userid,
  ) async {
    final blacklist = ['anonymous', '*deleted*'];

    if (blacklist.contains(username)) {
      // print('''
      //   username check for blacklisted item:
      //     userId: ${data.userId},
      //     username: ${data.username}
      // ''');
      return false;
    }

    final userQuery =
        await _usersRef.where('username', isEqualTo: username).get();
    if (userQuery.docs.isNotEmpty && userQuery.docs.first.id != userid) {
      // print('''
      //   username check for already taken username:
      //     userId: ${data.userId},
      //     username: ${data.username}
      // ''');
      return false;
    }

    // print('''
    //   username check for available username:
    //     userId: ${data.userId},
    //     username: ${data.username}
    // ''');
    return true;
  }

  @override
  Future<bool> userEmailExists(String email) async {
    final userSnapshot = await _usersRef.where('email', isEqualTo: email).get();

    return userSnapshot.docs.isNotEmpty;
  }

  @override
  Future<void> createUser(UserModel user) async {
    try {
      await _analytics.logEvent(name: 'onboarding_user');

      final userAlreadyExists = (await _usersRef.doc(user.id).get()).exists;
      if (userAlreadyExists) {
        return;
      }

      final usernameAvailable = await checkUsernameAvailability(
        user.username.toString(),
        user.id,
      );
      if (!usernameAvailable) {
        throw HandleAlreadyExistsException(
          'username availability check failed',
        );
      }

      await _usersRef.doc(user.id).set(user.toJson());
    } catch (e, s) {
      logger.error(
        'createUser',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteUser(String userId) async {
    try {
      await _analytics.logEvent(
        name: 'delete_user',
        parameters: {
          'user_id': userId,
        },
      );
      await _usersRef.doc(userId).delete();
    } catch (e, s) {
      logger.error('deleteUser', error: e, stackTrace: s);
    }
  }

  @override
  @Cached(ttl: 60) // 1 minute
  Future<Option<UserModel>> getUserByUsername(String? username) async {
    if (username == null) return const None();

    final userSnapshots =
        await _usersRef.where('username', isEqualTo: username).get();

    if (userSnapshots.docs.isNotEmpty) {
      return Option.of(UserModel.fromDoc(userSnapshots.docs.first));
    }

    return const None();
  }

  @override
  @Cached(ttl: 120) // 2 minute
  Future<Option<UserModel>> getUserById(String userId) async {
    final userSnapshot = await _usersRef.doc(userId).get();

    if (!userSnapshot.exists) {
      return const None();
    }

    try {
      final user = UserModel.fromDoc(userSnapshot);
      return Option.of(user);
    } catch (e, s) {
      logger.error(
        'getUserById',
        error: e,
        stackTrace: s,
      );
      return const None();
    }
  }

  @override
  Future<List<UserModel>> searchUsersByLocation({
    required double lat,
    required double lng,
    int radiusInMeters = 100 * 1000, // 100km
    int limit = 30,
    String? lastUserId,
  }) async {
    final range = getGeohashRange(
      latitude: lat,
      longitude: lng,
      distance: radiusInMeters ~/ 1000,
    );

    if (lastUserId != null) {
      final documentSnapshot = await _usersRef.doc(lastUserId).get();

      final usersSnapshot = await _usersRef
          .orderBy('geohash')
          .where('geohash', isGreaterThanOrEqualTo: range.lower)
          .where('geohash', isLessThanOrEqualTo: range.upper)
          .limit(limit)
          .startAfterDocument(documentSnapshot)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        return [];
      }

      final usersWithFP = usersSnapshot.docs.map(UserModel.fromDoc).toList();

      final users = usersWithFP
          .map((user) {
            final filteredUser = switch (user.location) {
              None() => null,
              Some(:final value) => (() {
                  // We have to filter out a few false positives due to GeoHash
                  // accuracy, but most will match
                  final distanceInKm = geoDistance(
                    Point(latitude: value.lat, longitude: value.lng),
                    Point(latitude: lat, longitude: lng),
                  );

                  final distanceInM = distanceInKm * 1000;
                  if (distanceInM > radiusInMeters) {
                    return null;
                  }

                  return user;
                })(),
            };

            return filteredUser;
          })
          .where((e) => e != null)
          .whereType<UserModel>()
          .toList();

      return users;
    } else {
      final usersSnapshot = await _usersRef
          .orderBy('geohash')
          .where('geohash', isGreaterThanOrEqualTo: range.lower)
          .where('geohash', isLessThanOrEqualTo: range.upper)
          .limit(limit)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        return [];
      }

      final usersWithFP = usersSnapshot.docs.map(UserModel.fromDoc).toList();

      final users = usersWithFP
          .map((user) {
            final filteredUser = switch (user.location) {
              None() => null,
              Some(:final value) => (() {
                  // We have to filter out a few false positives due to GeoHash
                  // accuracy, but most will match
                  final distanceInKm = geoDistance(
                    Point(latitude: value.lat, longitude: value.lng),
                    Point(latitude: lat, longitude: lng),
                  );

                  final distanceInM = distanceInKm * 1000;
                  if (distanceInM > radiusInMeters) {
                    return null;
                  }

                  return user;
                })(),
            };

            return filteredUser;
          })
          .where((e) => e != null)
          .whereType<UserModel>()
          .toList();

      return users;
    }
  }

  @override
  @cached
  Future<List<UserModel>> getBookingLeaders() async {
    try {
      final leadersSnapshot = await _leadersRef.doc('leaders').get();

      final leadingUsernames =
          leadersSnapshot.getOrElse('bookingLeaders', <dynamic>[]);

      final leaders = await Future.wait(
        leadingUsernames.map(
          (username) async {
            final user = await getUserByUsername(username as String);
            return user;
          },
        ),
      );

      return leaders
          .whereType<Some<UserModel>>()
          .map((e) => e.toNullable())
          .toList();
    } catch (e, s) {
      logger.error('getBookingLeaders', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  @cached
  Future<List<UserModel>> getBookerLeaders() async {
    try {
      final leadersSnapshot = await _leadersRef.doc('leaders').get();

      final leadingUsernames =
          leadersSnapshot.getOrElse('bookerLeaders', <dynamic>[]);

      final leaders = await Future.wait(
        leadingUsernames.map(
          (username) async {
            final user = await getUserByUsername(username as String);
            return user;
          },
        ),
      );

      return leaders
          .whereType<Some<UserModel>>()
          .map((e) => e.toNullable())
          .toList();
    } catch (e, s) {
      logger.error('getBookerLeaders', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  @cached
  Future<List<UserModel>> getFeaturedPerformers() async {
    try {
      final leadersSnapshot = await _leadersRef.doc('leaders').get();

      final leadingUsernames =
          leadersSnapshot.getOrElse('featuredPerformers', <dynamic>[]);

      final leaders = await Future.wait(
        leadingUsernames.map(
          (username) async {
            final user = await getUserByUsername(username as String);
            return user;
          },
        ),
      );

      return leaders
          .whereType<Some<UserModel>>()
          .map((e) => e.toNullable())
          .toList();
    } catch (e, s) {
      logger.error('getFeaturedPerformers', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  @Cached(ttl: 60 * 5) // 5 minute
  Future<List<Opportunity>> getFeaturedOpportunities() async {
    final leadersSnapshot = await _leadersRef.doc('leaders').get();
    final leadingOps =
        leadersSnapshot.getOrElse('featuredOpportunities', <dynamic>[]);

    final ops = await Future.wait(
      leadingOps.map(
        (opId) async {
          final op = await getOpportunityById(opId as String);
          return op;
        },
      ),
    );

    final iliasOps = await getOpportunitiesByUserId(tccUserId);

    final featured =
        ops.whereType<Some<Opportunity>>().map((e) => e.toNullable()).toList();

    return featured
      ..addAll(iliasOps)
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  @override
  Future<void> updateUserData(UserModel user) async {
    try {
      await _analytics.logEvent(name: 'user_data_update');
      final isUsernameAvailable =
          await checkUsernameAvailability(user.username.toString(), user.id);
      if (!isUsernameAvailable) {
        throw HandleAlreadyExistsException(
          'username availability check failed',
        );
      }

      await _usersRef.doc(user.id).set(user.toJson(), SetOptions(merge: true));
    } catch (e, s) {
      logger.error('updateUserData', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  Future<Option<PerformerCategory>> classifyPerformer(String userId) async {
    final user = (await getUserById(userId)).toNullable();
    if (user == null) {
      return const None();
    }

    final totalAudience = user.socialFollowing.audienceSize;
    final bookings = await getBookingsByRequestee(userId);

    final venueCapacities = await Future.wait(
      bookings.map((booking) async {
        final requesterId = booking.requesterId;
        return switch (requesterId) {
          None() => Future.value({'capacity': 0, 'startTime': DateTime.now()}),
          Some(:final value) => (() async {
              final requester = await getUserById(value);
              final capacity = requester.flatMap((user) {
                return user.venueInfo.flatMap((venueInfo) {
                  return venueInfo.capacity;
                });
              }).getOrElse(() => 0);

              return {
                'capacity': capacity,
                'startTime': booking.startTime,
              };
            })(),
        };
      }),
    );

    final capacities =
        venueCapacities.where((obj) => obj['capacity'] != 0).toList();

    final category = categorizeWithWeightedDate(totalAudience, capacities);

    return Option.of(category);
  }

  @override
  Future<List<Activity>> getActivities(
    String userId, {
    int limit = 20,
    String? lastActivityId,
  }) async {
    if (lastActivityId != null) {
      final documentSnapshot = await _activitiesRef.doc(lastActivityId).get();

      final activitiesSnapshot = await _activitiesRef
          .orderBy('timestamp', descending: true)
          .where('toUserId', isEqualTo: userId)
          .limit(limit)
          .startAfterDocument(documentSnapshot)
          .get();

      final activities = activitiesSnapshot.docs
          .map((activity) {
            try {
              return Activity.fromDoc(activity);
            } catch (e) {
              // if (kDebugMode) {
              //   logger.error('getActivities', error: e, stackTrace: s);
              // }
              return null;
            }
          })
          .where((element) => element != null)
          .whereType<Activity>()
          .toList();

      return activities;
    } else {
      final activitiesSnapshot = await _activitiesRef
          .orderBy('timestamp', descending: true)
          .where('toUserId', isEqualTo: userId)
          .limit(limit)
          .get();

      final activities = activitiesSnapshot.docs
          .map((activity) {
            try {
              return Activity.fromDoc(activity);
            } catch (e) {
              // if (kDebugMode) {
              //   logger.error('getActivities', error: e, stackTrace: s);
              // }
              return null;
            }
          })
          .where((element) => element != null)
          .whereType<Activity>()
          .toList();

      return activities;
    }
  }

  @override
  Stream<Activity> activitiesObserver(
    String userId, {
    int limit = 20,
  }) async* {
    final activitiesSnapshotObserver = _activitiesRef
        .orderBy('timestamp', descending: true)
        .where('toUserId', isEqualTo: userId)
        .limit(limit)
        .snapshots();

    final activitiesObserver = activitiesSnapshotObserver
        .map((event) {
          return event.docChanges
              .where(
            (DocumentChange<Map<String, dynamic>> element) =>
                element.type == DocumentChangeType.added,
          )
              .map((DocumentChange<Map<String, dynamic>> element) {
            try {
              return Activity.fromDoc(element.doc);
            } catch (e) {
              // if (kDebugMode) {
              //   logger.error('activitiesObserver', error: e, stackTrace: s);
              // }
              return null;
            }
            // if (element.type == DocumentChangeType.modified) {}
            // if (element.type == DocumentChangeType.removed) {}
          });
        })
        .flatMap(Stream.fromIterable)
        .whereType<Activity>();

    yield* activitiesObserver;
  }

  @override
  Future<void> addActivity({
    required String currentUserId,
    required ActivityType type,
    required String visitedUserId,
  }) async {
    await _analytics.logEvent(
      name: 'new_activity',
      parameters: {
        'from_user_id': currentUserId,
        'to_user_id': visitedUserId,
        'type': EnumToString.convertToString(type),
      },
    );

    await _activitiesRef.add({
      'toUserId': visitedUserId,
      'fromUserId': currentUserId,
      'timestamp': Timestamp.now(),
      'type': EnumToString.convertToString(type),
    });
  }

  @override
  Future<void> markActivityAsRead(Activity activity) async {
    if (activity.markedRead) return;

    await _analytics.logEvent(
      name: 'activity_read',
      parameters: {
        'activity_id': activity.id,
      },
    );
    await _activitiesRef.doc(activity.id).update({
      'markedRead': true,
    });
  }

  @override
  @Cached(where: _asyncShouldCache)
  Future<bool> isVerified(String userId) async {
    try {
      final verifiedBadgeSentDoc = await _badgesSentRef
          .doc(userId)
          .collection('badges')
          .doc(verifiedBadgeId)
          .get();

      final isVerified = verifiedBadgeSentDoc.exists;

      return isVerified;
    } on FirebaseException {
      return false;
    }
  }

  @override
  Future<void> verifyUser(String userId) async {
    try {
      await _analytics.logEvent(
        name: 'user_verified',
        parameters: {
          'user_id': userId,
        },
      );

      await _badgesSentRef
          .doc(userId)
          .collection('badges')
          .doc(verifiedBadgeId)
          .set({
        'badgeId': verifiedBadgeId,
        'timestamp': Timestamp.now(),
      });
    } catch (e, s) {
      logger.error('verifyUser', error: e, stackTrace: s);
    }
  }

  @override
  Stream<Badge> userBadgesObserver(
    String userId, {
    int limit = 30,
  }) async* {
    final userBadgesSnapshotObserver = _badgesSentRef
        .doc(userId)
        .collection('badges')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();

    final userBadgesObserver = userBadgesSnapshotObserver.map((event) {
      return event.docChanges
          .where(
        (DocumentChange<Map<String, dynamic>> element) =>
            element.type == DocumentChangeType.added,
      )
          .map((DocumentChange<Map<String, dynamic>> element) async {
        final badgeId = element.doc.id;
        // print('BADGE ID { $badgeId }');
        final badgeSnapshot = await _badgesRef.doc(badgeId).get();
        return Badge.fromDoc(badgeSnapshot);
      });
    }).flatMap(Stream.fromIterable);

    await for (final badge in userBadgesObserver) {
      try {
        yield await badge;
      } catch (error, stack) {
        yield* Stream.error(error, stack);
      }
    }
  }

  @override
  Future<List<Badge>> getUserBadges(
    String userId, {
    int limit = 30,
    String? lastBadgeId,
  }) async {
    if (lastBadgeId != null) {
      final documentSnapshot = await _badgesSentRef
          .doc(userId)
          .collection('badges')
          .doc(lastBadgeId)
          .get();

      final userBadgesSnapshot = await _badgesSentRef
          .doc(userId)
          .collection('badges')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .startAfterDocument(documentSnapshot)
          .get();

      final userBadges = Future.wait(
        userBadgesSnapshot.docs.map((doc) async {
          final badgeId = doc.getOrElse('badgeId', '');
          final badgeSnapshot = await _badgesRef.doc(badgeId).get();
          return Badge.fromDoc(badgeSnapshot);
        }).toList(),
      );
      return userBadges;
    } else {
      final userBadgesSnapshot = await _badgesSentRef
          .doc(userId)
          .collection('badges')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      final userBadges = Future.wait(
        userBadgesSnapshot.docs.map((doc) async {
          final badgeId = doc.id;
          final badgeSnapshot = await _badgesRef.doc(badgeId).get();
          return Badge.fromDoc(badgeSnapshot);
        }).toList(),
      );
      return userBadges;
    }
  }

  @override
  Future<void> createBooking(
    Booking booking,
  ) async {
    try {
      await _analytics.logEvent(
        name: 'booking_created',
        parameters: {
          'requestee_id': booking.requesteeId,
          'rate': booking.rate,
          'total': booking.totalCost,
          'booking_id': booking.id,
        },
      );
      await _bookingsRef.doc(booking.id).set(booking.toJson());
    } catch (e, s) {
      logger.e('createBooking', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  @cached
  Future<Option<Booking>> getBookingById(
    String bookRequestId,
  ) async {
    try {
      final bookingSnapshot = await _bookingsRef.doc(bookRequestId).get();
      final bookingRequest = Booking.fromDoc(bookingSnapshot);

      return Option.of(bookingRequest);
    } catch (e, s) {
      logger.error(
        'Error getting booking by id',
        error: e,
        stackTrace: s,
      );
      return const None();
    }
  }

  @override
  @cached
  Future<List<Booking>> getBookingsByEventId(String eventId) async {
    final bookingSnapshot =
        await _bookingsRef.where('referenceEventId', isEqualTo: eventId).get();

    final bookingRequests = bookingSnapshot.docs.map(Booking.fromDoc).toList();

    return bookingRequests;
  }

  @override
  @Cached(ttl: 60) // 1 minute
  Future<List<Booking>> getBookingsByRequesterRequestee(
    String requesterId,
    String requesteeId, {
    int limit = 20,
    String? lastBookingRequestId,
    BookingStatus? status,
  }) async {
    final bookingSnapshot = await (() {
      if (status == null) {
        return _bookingsRef
            .where(
              'requesterId',
              isEqualTo: requesterId,
            )
            .where(
              'requesteeId',
              isEqualTo: requesteeId,
            )
            .orderBy('startTime', descending: true)
            .get();
      }

      return _bookingsRef
          .where(
            'requesterId',
            isEqualTo: requesterId,
          )
          .where(
            'requesteeId',
            isEqualTo: requesteeId,
          )
          .where('status', isEqualTo: EnumToString.convertToString(status))
          .orderBy('startTime', descending: true)
          .get();
    })();

    final bookingRequests = bookingSnapshot.docs.map(Booking.fromDoc).toList();

    return bookingRequests;
  }

  @override
  @Cached(ttl: 60) // 1 minute
  Future<List<Booking>> getBookingsByRequester(
    String userId, {
    int limit = 20,
    String? lastBookingRequestId,
    BookingStatus? status,
  }) async {
    try {
      final bookingSnapshot = await (() {
        if (status == null) {
          return _bookingsRef
              .where(
                'requesterId',
                isEqualTo: userId,
              )
              .orderBy('startTime', descending: true)
              .limit(limit)
              .get();
        }

        return _bookingsRef
            .where(
              'requesterId',
              isEqualTo: userId,
            )
            .where('status', isEqualTo: EnumToString.convertToString(status))
            .orderBy('startTime', descending: true)
            .limit(limit)
            .get();
      })();

      final bookingRequests =
          bookingSnapshot.docs.map(Booking.fromDoc).toList();

      return bookingRequests;
    } catch (e, s) {
      logger.error(
        'error getting bookings by requester',
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }

  @override
  Stream<Booking> getBookingsByRequesterObserver(
    String userId, {
    int limit = 20,
    BookingStatus? status,
  }) async* {
    final bookingsSnapshotObserver = (() {
      if (status == null) {
        return _bookingsRef
            .where('requesterId', isEqualTo: userId)
            .orderBy('startTime', descending: true)
            .limit(limit)
            .snapshots();
      }

      return _bookingsRef
          .where('requesterId', isEqualTo: userId)
          .where('status', isEqualTo: EnumToString.convertToString(status))
          .orderBy('startTime', descending: true)
          .limit(limit)
          .snapshots();
    })();

    final bookingsObserver = bookingsSnapshotObserver.map((event) {
      return event.docChanges
          .where(
        (DocumentChange<Map<String, dynamic>> element) =>
            element.type == DocumentChangeType.added,
      )
          .map((DocumentChange<Map<String, dynamic>> element) async {
        final bookingId = element.doc.id;
        // print('BOOKING ID { $bookingId }');
        final bookingSnapshot = await _bookingsRef.doc(bookingId).get();
        return Booking.fromDoc(bookingSnapshot);
      });
    }).flatMap(Stream.fromIterable);

    await for (final booking in bookingsObserver) {
      try {
        yield await booking;
      } catch (error, stack) {
        yield* Stream.error(error, stack);
      }
    }
  }

  @override
  @Cached(ttl: 60) // 1 minute
  Future<List<Booking>> getBookingsByRequestee(
    String userId, {
    int limit = 20,
    String? lastBookingRequestId,
    BookingStatus? status,
  }) async {
    try {
      final bookingSnapshot = await (() {
        if (status == null) {
          return _bookingsRef
              .where(
                'requesteeId',
                isEqualTo: userId,
              )
              .orderBy('startTime', descending: true)
              .limit(limit)
              .get();
        }

        return _bookingsRef
            .where(
              'requesteeId',
              isEqualTo: userId,
            )
            .where('status', isEqualTo: EnumToString.convertToString(status))
            .orderBy('startTime', descending: true)
            .limit(limit)
            .get();
      })();

      final bookingRequests =
          bookingSnapshot.docs.map(Booking.fromDoc).toList();

      return bookingRequests;
    } catch (e, s) {
      logger.error(
        'error getting bookings by requestee',
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }

  @override
  Stream<Booking> getBookingsByRequesteeObserver(
    String userId, {
    int limit = 20,
    BookingStatus? status,
  }) async* {
    final bookingsSnapshotObserver = (() {
      if (status == null) {
        return _bookingsRef
            .where('requesteeId', isEqualTo: userId)
            .orderBy('startTime', descending: true)
            .limit(limit)
            .snapshots();
      }

      return _bookingsRef
          .where('requesteeId', isEqualTo: userId)
          .where('status', isEqualTo: EnumToString.convertToString(status))
          .orderBy('startTime', descending: true)
          .limit(limit)
          .snapshots();
    })();

    final bookingsObserver = bookingsSnapshotObserver.map((event) {
      return event.docChanges
          .where(
        (DocumentChange<Map<String, dynamic>> element) =>
            element.type == DocumentChangeType.added,
      )
          .map((DocumentChange<Map<String, dynamic>> element) async {
        final bookingId = element.doc.id;
        // print('BOOKING ID { $bookingId }');
        final bookingSnapshot = await _bookingsRef.doc(bookingId).get();
        return Booking.fromDoc(bookingSnapshot);
      });
    }).flatMap(Stream.fromIterable);

    await for (final booking in bookingsObserver) {
      try {
        yield await booking;
      } catch (error, stack) {
        yield* Stream.error(error, stack);
      }
    }
  }

  @override
  Future<void> updateBooking(Booking booking) async {
    try {
      await _analytics.logEvent(
        name: 'update_booking',
        parameters: {
          'status': EnumToString.convertToString(booking.status),
        },
      );
      await _bookingsRef.doc(booking.id).set(booking.toJson());
    } catch (e, s) {
      logger.error(
        'error updating booking',
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> createService(Service service) async {
    try {
      await _analytics.logEvent(
        name: 'service_created',
        parameters: {
          'service_id': service.id,
          'user_id': service.userId,
          'title': service.title,
          'description': service.description,
          'rate': service.rate,
          'rate_type': service.rateType.name,
        },
      );
      await _servicesRef
          .doc(service.userId)
          .collection('userServices')
          .doc(service.id)
          .set(service.toJson());
    } catch (e, s) {
      logger.error('createService', error: e, stackTrace: s);
    }
  }

  @override
  Future<void> deleteService(String userId, String serviceId) async {
    try {
      await _analytics.logEvent(
        name: 'service_deleted',
      );
      await _servicesRef
          .doc(userId)
          .collection('userServices')
          .doc(serviceId)
          .update({
        'userId': userId,
        'deleted': true,
      });
    } catch (e, s) {
      logger.error('deleteService', error: e, stackTrace: s);
    }
  }

  @override
  Future<Option<Service>> getServiceById(
    String userId,
    String serviceId,
  ) async {
    try {
      final serviceSnapshot = await _servicesRef
          .doc(userId)
          .collection('userServices')
          .doc(serviceId)
          .get();

      final service = Service.fromDoc(serviceSnapshot);

      return Option.of(service);
    } catch (e, s) {
      logger.error(
        'getServiceById - $userId - $serviceId',
        error: e,
        stackTrace: s,
      );
      return const None();
    }
  }

  @override
  Future<List<Service>> getUserServices(String userId) async {
    try {
      await _analytics.logEvent(
        name: 'get_user_services',
        parameters: {
          'user_id': userId,
        },
      );

      final userServicesSnapshot = await _servicesRef
          .doc(userId)
          .collection('userServices')
          .where('deleted', isNotEqualTo: true)
          .get();

      final services = userServicesSnapshot.docs.map(Service.fromDoc).toList();

      return services;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> updateService(Service service) async {
    try {
      await _analytics.logEvent(
        name: 'service_updated',
      );
      await _servicesRef
          .doc(service.userId)
          .collection('userServices')
          .doc(service.id)
          .set(service.toJson());
    } catch (e, s) {
      logger.error('updateService', error: e, stackTrace: s);
    }
  }

  @override
  @cached
  Future<Option<Opportunity>> getOpportunityById(
    String opportunityId,
  ) async {
    try {
      final opportunitySnapshot =
          await _opportunitiesRef.doc(opportunityId).get();

      if (!opportunitySnapshot.exists) {
        return const None();
      }

      final opportunity = Opportunity.fromDoc(opportunitySnapshot);

      return Option.of(opportunity);
    } catch (e, s) {
      logger.error('getOpportunityById', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  Future<List<Opportunity>> getOpportunities({
    int limit = 20,
    String? lastOpportunityId,
  }) async {
    await _analytics.logEvent(
      name: 'get_opportunities',
    );

    if (lastOpportunityId != null) {
      final documentSnapshot =
          await _opportunitiesRef.doc(lastOpportunityId).get();

      final opportunitiesSnapshot = await _opportunitiesRef
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .startAfterDocument(documentSnapshot)
          .get();

      final opportunities =
          opportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

      return opportunities;
    }

    final opportunitiesSnapshot = await _opportunitiesRef
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    final opportunities =
        opportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

    return opportunities;
  }

  @override
  @Cached(ttl: 300) // 5 minutes
  Future<List<Opportunity>> getOpportunitiesByUserId(
    String userId, {
    int limit = 20,
    String? lastOpportunityId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'get_opportunities_by_user_id',
        parameters: {
          'user_id': userId,
        },
      );

      if (lastOpportunityId != null) {
        final documentSnapshot =
            await _opportunitiesRef.doc(lastOpportunityId).get();

        final opportunitiesSnapshot = await _opportunitiesRef
            .where('userId', isEqualTo: userId)
            .where('deleted', isEqualTo: false)
            .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
            .orderBy('timestamp', descending: true)
            .limit(limit)
            .startAfterDocument(documentSnapshot)
            .get();

        final opportunities =
            opportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

        return opportunities;
      }

      final userOpportunitiesSnapshot = await _opportunitiesRef
          .where('userId', isEqualTo: userId)
          .where('deleted', isEqualTo: false)
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
          .orderBy('startTime', descending: true)
          .limit(limit)
          .get();

      logger.i(
        'userOpportunitiesSnapshot ${userOpportunitiesSnapshot.docs.length}',
      );

      final opportunities =
          userOpportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

      return opportunities;
    } catch (e, s) {
      logger.e('getUserOpportunities', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  @Cached(where: _asyncShouldCache)
  Future<bool> isUserAppliedForOpportunity({
    required String userId,
    required String opportunityId,
  }) async {
    try {
      final userSnapshot = await _opportunitiesRef
          .doc(opportunityId)
          .collection('interestedUsers')
          .doc(userId)
          .get();

      return userSnapshot.exists;
    } catch (e, s) {
      logger.error('isAppliedForOpportunity', error: e, stackTrace: s);
      return false;
    }
  }

  @override
  Future<List<UserModel>> getInterestedUsers(Opportunity opportunity) async {
    try {
      await _analytics.logEvent(
        name: 'get_interested_users',
        parameters: {
          'opportunity_id': opportunity.id,
        },
      );

      final interestedUsersSnapshot = await _opportunitiesRef
          .doc(opportunity.id)
          .collection('interestedUsers')
          .get();

      final interestedUsers = (await Future.wait(
        interestedUsersSnapshot.docs.map((doc) async {
          try {
            final userSnapshot = await _usersRef.doc(doc.id).get();
            return UserModel.fromDoc(userSnapshot);
          } catch (e, s) {
            logger.error('getInterestedUsers', error: e, stackTrace: s);
            return null;
          }
        }),
      ))
          .whereType<UserModel>()
          .toList();

      return interestedUsers;
    } catch (e, s) {
      logger.error('getInterestedUsers', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  Future<void> applyForOpportunity({
    required String userId,
    required String userComment,
    required Opportunity opportunity,
  }) async {
    try {
      logger.debug(
        'applyForOpportunity, userId: $userId, opportunity: $opportunity',
      );
      await _analytics.logEvent(
        name: 'apply_for_opportunity',
        parameters: {
          'user_id': userId,
          'opportunity_id': opportunity.id,
        },
      );

      await _opportunitiesRef
          .doc(opportunity.id)
          .collection('interestedUsers')
          .doc(userId)
          .set({
        'timestamp': Timestamp.now(),
        'userComment': userComment,
      });

      await _opportunityFeedsRef
          .doc(userId)
          .collection('opportunities')
          .doc(opportunity.id)
          .set(
        {
          'touched': 'like',
          'userComment': userComment,
        },
        SetOptions(merge: true),
      );
    } catch (e, s) {
      logger.error('applyForOpporunities', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  Future<void> dislikeOpportunity({
    required Opportunity opportunity,
    required String userId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'dislike_opportunity',
        parameters: {
          'user_id': userId,
          'opportunity_id': opportunity.id,
        },
      );

      await _opportunityFeedsRef
          .doc(userId)
          .collection('opportunities')
          .doc(opportunity.id)
          .update({
        'touched': 'dislike',
      });
    } catch (e, s) {
      logger.error('applyForOpporunities', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  @Cached(ttl: 60) // 1 minute
  Future<List<Opportunity>> getOpportunityFeedByUserId(
    String userId, {
    int limit = 20,
    String? lastOpportunityId,
  }) async {
    await _analytics.logEvent(
      name: 'get_opportunity_feed_by_user_id',
      parameters: {
        'user_id': userId,
      },
    );

    if (lastOpportunityId != null) {
      final documentSnapshot = await _opportunityFeedsRef
          .doc(userId)
          .collection('opportunities')
          .doc(lastOpportunityId)
          .get();

      final opportunitiesSnapshot = await _opportunityFeedsRef
          .doc(userId)
          .collection('opportunities')
          .orderBy('startTime', descending: true)
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
          .where('touched', isNull: true)
          .limit(limit)
          .startAfterDocument(documentSnapshot)
          .get();

      final opportunities =
          opportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

      return opportunities;
    }

    final opportunitiesSnapshot = await _opportunityFeedsRef
        .doc(userId)
        .collection('opportunities')
        .orderBy('startTime', descending: true)
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
        .where('touched', isNull: true)
        .limit(limit)
        .get();

    final opportunities =
        opportunitiesSnapshot.docs.map(Opportunity.fromDoc).toList();

    return opportunities;
  }

  @override
  Future<List<Opportunity>> getAppliedOpportunitiesByUserId(
    String userId, {
    int limit = 20,
    String? lastOpportunityId,
  }) async {
    final appliedOpportunitiesSnapshot = await _opportunityFeedsRef
        .doc(userId)
        .collection('opportunities')
        .orderBy('startTime', descending: true)
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.now())
        .where('touched', isEqualTo: 'like')
        .limit(limit)
        .get();

    final opportunities = appliedOpportunitiesSnapshot.docs
        .map(
          Opportunity.fromDoc,
        )
        .toList();

    return opportunities;
  }

  @override
  Future<int> getUserOpportunityQuota(String userId) async {
    final quotaSnap = await _creditsRef.doc(userId).get();
    final quota = quotaSnap.getOrElse('opportunityQuota', 0);

    return quota;
  }

  @override
  Stream<int> getUserOpportunityQuotaObserver(String userId) async* {
    final quotaSnapObserver = _creditsRef.doc(userId).snapshots();

    final quotaObserver = quotaSnapObserver.map((event) {
      final data = event.data();

      return data?.getOrElse('opportunityQuota', 0) ?? 0;
    });

    yield* quotaObserver;
  }

  @override
  Future<void> decrementUserOpportunityQuota(String userId) async {
    try {
      await _creditsRef.doc(userId).update({
        'opportunityQuota': FieldValue.increment(-1),
      });
    } catch (e, s) {
      logger.error('decrementUserOpportunityQuota', error: e, stackTrace: s);
    }
  }

  @override
  Future<void> createOpportunity(Opportunity op) async {
    try {
      await _analytics.logEvent(
        name: 'create_opportunity',
        parameters: {
          'user_id': op.userId,
          'opportunity_id': op.id,
        },
      );

      await _opportunitiesRef.doc(op.id).set(op.toJson());
    } catch (e, s) {
      logger.error('createOpportunity', error: e, stackTrace: s);
      rethrow;
    }
  }

  @override
  Future<void> copyOpportunityToFeeds(Opportunity opportunity) async {
    try {
      await _analytics.logEvent(
        name: 'copy_opportunity_to_feeds',
        parameters: {
          'user_id': opportunity.userId,
          'opportunity_id': opportunity.id,
        },
      );

      final usersSnap = await _usersRef
          .where(
            'deleted',
            isNotEqualTo: true,
          )
          .get();

      await Future.wait(
        usersSnap.docs.map(
          (userDoc) async {
            if (userDoc.id == opportunity.userId) {
              return;
            }

            if (userDoc.getOrElse('email', '').endsWith('tapped.ai')) {
              return;
            }

            await _opportunityFeedsRef
                .doc(userDoc.id)
                .collection('opportunities')
                .doc(opportunity.id)
                .set(opportunity.toJson());
          },
        ),
      );
    } catch (e, s) {
      logger.error('copyOpportunityToFeeds', error: e, stackTrace: s);
    }
  }

  @override
  Future<void> deleteOpportunity(String opportunityId) async {
    try {
      await _analytics.logEvent(
        name: 'delete_opportunity',
        parameters: {
          'opportunity_id': opportunityId,
        },
      );

      await _opportunitiesRef.doc(opportunityId).update({
        'deleted': true,
      });
    } catch (e, s) {
      logger.error('deleteOpportunity', error: e, stackTrace: s);
    }
  }

  @override
  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    await _analytics.logEvent(
      name: 'block_user',
      parameters: {
        'user_id': currentUserId,
        'blocked_user_id': blockedUserId,
      },
    );

    await _blockerRef
        .doc(currentUserId)
        .collection(blockerSubcollection)
        .doc(blockedUserId)
        .set({
      'timestamp': Timestamp.now(),
    });
  }

  @override
  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    await _analytics.logEvent(
      name: 'unblock_user',
      parameters: {
        'user_id': currentUserId,
        'blocked_user_id': blockedUserId,
      },
    );

    await _blockerRef
        .doc(currentUserId)
        .collection(blockerSubcollection)
        .doc(blockedUserId)
        .delete();
  }

  @override
  Future<bool> isBlocked({
    required String blockedUserId,
    required String currentUserId,
  }) async {
    final blockedUserSnapshot = await _blockerRef
        .doc(currentUserId)
        .collection(blockerSubcollection)
        .doc(blockedUserId)
        .get();

    return blockedUserSnapshot.exists;
  }

  @override
  Future<void> reportUser({
    required UserModel reported,
    required UserModel reporter,
  }) async {
    await _analytics.logEvent(
      name: 'report_user',
      parameters: {
        'reporter_id': reporter.id,
        'reported_id': reported.id,
      },
    );
    final reportHtml = '''
        <p>Report from:</p> 
        <p>${reporter.toJson()}<p> 
        <p>User:</p> 
        <p>${reported.toJson()}</p>
    ''';

    await _mailRef.add({
      'to': [
        'support@tapped.ai',
      ],
      'cc': [
        'johannes@tapped.ai',
        'ilias@tapped.ai',
      ],
      'message': {
        'subject': 'User Reported',
        'html': reportHtml,
      },
    });
  }

  @override
  Future<void> createBookerReview(BookerReview review) async {
    await _analytics.logEvent(
      name: 'create_booker_review',
      parameters: {
        'reviewer': review.performerId,
        'reviewee': review.bookerId,
        'type': review.type,
      },
    );

    await _reviewsRef
        .doc(review.bookerId)
        .collection(bookerReviewsSubcollection)
        .doc(review.id)
        .set(review.toMap());
  }

  @override
  Future<void> createPerformerReview(PerformerReview review) async {
    await _analytics.logEvent(
      name: 'create_performer_review',
      parameters: {
        'reviewer': review.bookerId,
        'reviewee': review.performerId,
        'type': review.type,
      },
    );

    await _reviewsRef
        .doc(review.performerId)
        .collection(performerReviewsSubcollection)
        .doc(review.id)
        .set(review.toMap());
  }

  @override
  @cached
  Future<Option<BookerReview>> getBookerReviewById({
    required String revieweeId,
    required String reviewId,
  }) async {
    try {
      final reviewSnapshot = await _reviewsRef
          .doc(revieweeId)
          .collection(bookerReviewsSubcollection)
          .doc(reviewId)
          .get();
      return reviewSnapshot.exists
          ? Option.of(BookerReview.fromDoc(reviewSnapshot))
          : const None();
    } catch (e, s) {
      logger.error(
        'error getting booker review by id',
        error: e,
        stackTrace: s,
      );
      return const None();
    }
  }

  @override
  @cached
  Future<List<BookerReview>> getBookerReviewsByBookerId(
    String bookerId, {
    int limit = 20,
    String? lastReviewId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'get_booker_reviews_by_booker_id',
        parameters: {
          'booker_id': bookerId,
        },
      );
      final reviewsQuery = _reviewsRef
          .doc(bookerId)
          .collection(bookerReviewsSubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (lastReviewId != null) {
        final lastReviewSnapshot = await _reviewsRef
            .doc(bookerId)
            .collection(bookerReviewsSubcollection)
            .doc(lastReviewId)
            .get();
        reviewsQuery.startAfterDocument(lastReviewSnapshot);
      }

      final reviewsSnapshot = await reviewsQuery.get();
      return reviewsSnapshot.docs.map(BookerReview.fromDoc).toList();
    } catch (e, s) {
      logger.error(
        'error getting booker reviews by booker id',
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }

  @override
  Stream<BookerReview> getBookerReviewsByBookerIdObserver(
    String bookerId, {
    int limit = 20,
  }) async* {
    try {
      final reviewsSnapshotObserver = _reviewsRef
          .doc(bookerId)
          .collection(bookerReviewsSubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots();

      final reviewsObserver = reviewsSnapshotObserver.map((event) {
        return event.docChanges
            .where(
          (DocumentChange<Map<String, dynamic>> element) =>
              element.type == DocumentChangeType.added,
        )
            .map((DocumentChange<Map<String, dynamic>> element) async {
          final reviewId = element.doc.id;
          // print('REVIEW ID { $reviewId }');

          final reviewSnapshot = await _reviewsRef
              .doc(bookerId)
              .collection(bookerReviewsSubcollection)
              .doc(reviewId)
              .get();

          return BookerReview.fromDoc(reviewSnapshot);
        });
      }).flatMap(Stream.fromIterable);

      await for (final review in reviewsObserver) {
        try {
          yield await review;
        } catch (error, stack) {
          yield* Stream.error(error, stack);
        }
      }
    } catch (e, s) {
      logger.error(
        'error getting booker reviews by booker id',
        error: e,
        stackTrace: s,
      );
      yield* const Stream.empty();
    }
  }

  @override
  @cached
  Future<Option<PerformerReview>> getPerformerReviewById({
    required String revieweeId,
    required String reviewId,
  }) async {
    try {
      final reviewSnapshot = await _reviewsRef
          .doc(revieweeId)
          .collection(performerReviewsSubcollection)
          .doc(reviewId)
          .get();
      return reviewSnapshot.exists
          ? Option.of(PerformerReview.fromDoc(reviewSnapshot))
          : const None();
    } catch (e, s) {
      logger.error(
        'error getting performer review by id',
        error: e,
        stackTrace: s,
      );
      return const None();
    }
  }

  @override
  @cached
  Future<List<PerformerReview>> getPerformerReviewsByPerformerId(
    String performerId, {
    int limit = 20,
    String? lastReviewId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'get_performer_reviews_by_performer_id',
        parameters: {
          'performer_id': performerId,
        },
      );
      final reviewsQuery = _reviewsRef
          .doc(performerId)
          .collection(performerReviewsSubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (lastReviewId != null) {
        final lastReviewSnapshot = await _reviewsRef
            .doc(performerId)
            .collection(performerReviewsSubcollection)
            .doc(lastReviewId)
            .get();
        reviewsQuery.startAfterDocument(lastReviewSnapshot);
      }

      final reviewsSnapshot = await reviewsQuery.get();
      return reviewsSnapshot.docs.map(PerformerReview.fromDoc).toList();
    } catch (e, s) {
      logger.error(
        'error getting performer reviews by performer id',
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }

  @override
  Stream<PerformerReview> getPerformerReviewsByPerformerIdObserver(
    String performerId, {
    int limit = 20,
  }) async* {
    try {
      final reviewsSnapshotObserver = _reviewsRef
          .doc(performerId)
          .collection(performerReviewsSubcollection)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots();

      final reviewsObserver = reviewsSnapshotObserver.map((event) {
        return event.docChanges
            .where(
          (DocumentChange<Map<String, dynamic>> element) =>
              element.type == DocumentChangeType.added,
        )
            .map((DocumentChange<Map<String, dynamic>> element) async {
          final reviewId = element.doc.id;
          // print('REVIEW ID { $reviewId }');
          final reviewSnapshot = await _reviewsRef
              .doc(performerId)
              .collection(performerReviewsSubcollection)
              .doc(reviewId)
              .get();

          return PerformerReview.fromDoc(reviewSnapshot);
        });
      }).flatMap(Stream.fromIterable);

      await for (final review in reviewsObserver) {
        try {
          yield await review;
        } catch (error, stack) {
          yield* Stream.error(error, stack);
        }
      }
    } catch (e, s) {
      logger.error(
        'error getting performer reviews by performer id',
        error: e,
        stackTrace: s,
      );
      yield* const Stream.empty();
    }
  }

  @override
  @Cached(where: _asyncShouldCache)
  Future<bool> isOnPremiumWailist(String userId) async {
    try {
      final docSnap = await _premiumWailistRef.doc(userId).get();
      return docSnap.exists;
    } catch (e, s) {
      logger.error(
        "can't check if a user is on the waitlist $userId",
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  Future<void> joinPremiumWaitlist(String userId) async {
    try {
      await _analytics.logEvent(
        name: 'join_premium_waitlist',
        parameters: {
          'user_id': userId,
        },
      );
      await _premiumWailistRef.doc(userId).set({
        'timestamp': Timestamp.now(),
      });
    } catch (e, s) {
      logger.error(
        "can't add user to the waitlist $userId",
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  Future<void> sendFeedback(
    String userId,
    UserFeedback feedback,
    String imageUrl,
  ) async {
    try {
      await _analytics.logEvent(
        name: 'send_feedback',
        parameters: {
          'user_id': userId,
        },
      );
      await _userFeedbackRef.add({
        'userId': userId,
        'timestamp': Timestamp.now(),
        'text': feedback.text,
        'screenshotUrl': imageUrl,
        'extra': feedback.extra,
      });
    } catch (e, s) {
      logger.error(
        "can't send feedback",
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  @Cached(where: _asyncShouldCache)
  Future<bool> hasUserSentContactRequest({
    required UserModel user,
    required UserModel venue,
  }) async {
    try {
      final contactRequestSnapshot = await _contactVenuesRef
          .doc(user.id)
          .collection('venuesContacted')
          .doc(venue.id)
          .get();

      return contactRequestSnapshot.exists;
    } catch (e, s) {
      logger.error(
        "can't check if user has sent contact request",
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  @override
  Future<List<UserModel>> getContactedVenues(String userId) async {
    try {
      final contactVenuesSnapshot = await _contactVenuesRef
          .doc(userId)
          .collection('venuesContacted')
          .get();

      final contactedVenues = await Future.wait(
        contactVenuesSnapshot.docs.map((doc) async {
          final venueSnapshot = await _usersRef.doc(doc.id).get();
          return UserModel.fromDoc(venueSnapshot);
        }),
      );

      return contactedVenues;
    } catch (e, s) {
      logger.error(
        "can't get contacted venues",
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }
}

class HandleAlreadyExistsException implements Exception {
  HandleAlreadyExistsException(this.cause);

  String cause;
}

class DateTimeConverter implements JsonConverter<DateTime, Timestamp> {
  const DateTimeConverter();

  @override
  DateTime fromJson(Timestamp json) {
    return json.toDate();
  }

  @override
  Timestamp toJson(DateTime object) {
    return Timestamp.fromDate(object);
  }
}

class OptionalDateTimeConverter
    implements JsonConverter<Option<DateTime>, Timestamp?> {
  const OptionalDateTimeConverter();

  @override
  Option<DateTime> fromJson(Timestamp? json) {
    return Option.fromNullable(json?.toDate());
  }

  @override
  Timestamp? toJson(Option<DateTime> object) {
    return object.fold(
      Timestamp.now,
      Timestamp.fromDate,
    );
  }
}

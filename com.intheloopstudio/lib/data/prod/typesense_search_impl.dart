import 'package:cached_annotation/cached_annotation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:intheloopapp/data/search_repository.dart';
import 'package:intheloopapp/domains/models/booking.dart';
import 'package:intheloopapp/domains/models/opportunity.dart';
import 'package:intheloopapp/domains/models/user_model.dart';
import 'package:intheloopapp/utils/app_logger.dart';
import 'package:intheloopapp/utils/typesense_config.dart';
import 'package:typesense/typesense.dart';

final _analytics = FirebaseAnalytics.instance;
final _fireStore = FirebaseFirestore.instance;
final usersRef = _fireStore.collection('users');
final bookingsRef = _fireStore.collection('bookings');
final opportunitiesRef = _fireStore.collection('opportunities');

class TypesenseSearchImpl extends SearchRepository {
  TypesenseSearchImpl() {
    client = Client(
      Configuration(
        TypesenseConfig.searchApiKey,
        nodes: {
          Node(
            Protocol.values.firstWhere(
              (p) => p.name == TypesenseConfig.protocol,
              orElse: () => Protocol.http,
            ),
            TypesenseConfig.host,
            port: int.parse(TypesenseConfig.port),
          ),
        },
        connectionTimeout: const Duration(seconds: 10),
      ),
    );
  }

  late final Client client;

  @cached
  Future<Booking> _getBooking(String bookingId) async {
    final bookingSnapshot = await bookingsRef.doc(bookingId).get();
    final booking = Booking.fromDoc(bookingSnapshot);

    return booking;
  }

  @cached
  Future<Opportunity> _getOpportunity(String opportunityId) async {
    final opportunitySnapshot = await opportunitiesRef.doc(opportunityId).get();
    final opportunity = Opportunity.fromDoc(opportunitySnapshot);

    return opportunity;
  }

  @override
  @Cached(ttl: 300) // 5 minutes
  Future<List<UserModel>> queryUsers(
    String input, {
    List<String>? labels,
    List<String>? genres,
    List<String>? venueGenres,
    List<String>? occupations,
    bool? unclaimed,
    int? minCapacity,
    int? maxCapacity,
    double? lat,
    double? lng,
    int radius = 50000,
    int limit = 20,
  }) async {
    final filterBy = <String>[];

    // Deleted filter
    filterBy.add('deleted:=false');

    // Labels filter
    if (labels != null && labels.isNotEmpty) {
      filterBy.add(
        "performerInfo.label:=[${labels.map((l) => "'$l'").join(', ')}]",
      );
    }

    // Genres filter
    if (genres != null && genres.isNotEmpty) {
      filterBy.add(
        "performerInfo.genres:=[${genres.map((g) => "'$g'").join(', ')}]",
      );
    }

    // Occupations filter
    if (occupations != null && occupations.isNotEmpty) {
      filterBy.add(
        "occupations:=[${occupations.map((o) => "'$o'").join(', ')}]",
      );
    }

    // Venue genres filter
    if (venueGenres != null && venueGenres.isNotEmpty) {
      filterBy.add(
        "venueInfo.genres:=[${venueGenres.map((g) => "'$g'").join(', ')}]",
      );
    }

    // Unclaimed filter
    if (unclaimed != null) {
      filterBy.add('unclaimed:=$unclaimed');
    }

    // Capacity filters
    if (minCapacity != null) {
      filterBy.add('venueInfo.capacity:>=$minCapacity');
    }

    if (maxCapacity != null) {
      filterBy.add('venueInfo.capacity:<=$maxCapacity');
    }

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by':
            'artistName,username,bio,performerInfo.label,venueInfo.type',
        'filter_by': filterBy.join(' && '),
        'per_page': limit,
      };

      // Add geo location filter and sorting if coordinates are provided
      if (lat != null && lng != null) {
        // Convert radius from meters to kilometers for Typesense
        final radiusKm = radius / 1000;
        // Add radius filter using correct Typesense syntax
        filterBy.add('location:($lat, $lng, $radiusKm km)');
        searchParameters['filter_by'] = filterBy.join(' && ');
        // Sort by distance from the specified location
        searchParameters['sort_by'] = 'location($lat, $lng):asc';
      } else {
        // Default sorting when no location is specified
        searchParameters['sort_by'] = '_text_match:desc';
      }

      final response =
          await client.collection('users').documents.search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final hits = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return _convertTypesenseDocumentToUserModel(document);
          }).toList() ??
          [];

      return hits;
    } catch (e) {
      logger.warning('Typesense search error: $e');
      return [];
    }
  }

  @override
  Future<List<Booking>> queryBookings(
    String input, {
    double? lat,
    double? lng,
    int radius = 50000,
  }) async {
    final filterBy = <String>[];

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by': 'title,description',
        'filter_by': filterBy.join(' && '),
      };

      // Add geo location filter if coordinates are provided
      if (lat != null && lng != null) {
        final radiusKm = radius / 1000;
        filterBy.add('location:($lat, $lng, $radiusKm km)');
        searchParameters['filter_by'] = filterBy.join(' && ');
        searchParameters['sort_by'] = 'location($lat, $lng):asc';
      }

      final response = await client
          .collection('bookings')
          .documents
          .search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final results = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return document['id'] as String;
          }).toList() ??
          [];

      final bookingResults = await Future.wait(
        results.map((bookingId) async => _getBooking(bookingId)),
      );

      return bookingResults;
    } catch (e) {
      logger.warning('Typesense bookings search error: $e');
      return [];
    }
  }

  @override
  Future<List<Opportunity>> queryOpportunities(
    String input, {
    double? lat,
    double? lng,
    int radius = 50000,
    DateTime? startTime,
  }) async {
    final filterBy = <String>[];

    // Deleted filter
    filterBy.add('deleted:=false');

    // Start time filter
    if (startTime != null) {
      final formattedStartTime = startTime.millisecondsSinceEpoch;
      logger.info('startTime>$formattedStartTime');
      filterBy.add('startTime:>$formattedStartTime');
    }

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by': 'title,description',
        'filter_by': filterBy.join(' && '),
      };

      // Add geo location filter if coordinates are provided
      if (lat != null && lng != null) {
        final radiusKm = radius / 1000;
        filterBy.add('location:($lat, $lng, $radiusKm km)');
        searchParameters['filter_by'] = filterBy.join(' && ');
        searchParameters['sort_by'] = 'location($lat, $lng):asc';
      }

      final response = await client
          .collection('opportunities')
          .documents
          .search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final results = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return document['id'] as String;
          }).toList() ??
          [];

      final opportunityResults = await Future.wait(
        results.map((opportunityId) async => _getOpportunity(opportunityId)),
      );

      return opportunityResults;
    } catch (e) {
      logger.warning('Typesense opportunities search error: $e');
      return [];
    }
  }

  @override
  Future<List<UserModel>> queryUsersInBoundingBox(
    String input, {
    required double swLatitude,
    required double swLongitude,
    required double neLatitude,
    required double neLongitude,
    List<String>? labels,
    List<String>? genres,
    List<String>? venueGenres,
    List<String>? occupations,
    int? minCapacity,
    int? maxCapacity,
    int limit = 100,
  }) async {
    final filterBy = <String>[];

    // Deleted filter
    filterBy.add('deleted:=false');

    // Labels filter
    if (labels != null && labels.isNotEmpty) {
      filterBy.add(
        "performerInfo.label:=[${labels.map((l) => "'$l'").join(', ')}]",
      );
    }

    // Genres filter
    if (genres != null && genres.isNotEmpty) {
      filterBy.add(
        "performerInfo.genres:=[${genres.map((g) => "'$g'").join(', ')}]",
      );
    }

    // Occupations filter
    if (occupations != null && occupations.isNotEmpty) {
      filterBy.add(
        "occupations:=[${occupations.map((o) => "'$o'").join(', ')}]",
      );
    }

    // Venue genres filter
    if (venueGenres != null && venueGenres.isNotEmpty) {
      filterBy.add(
        "venueInfo.genres:=[${venueGenres.map((g) => "'$g'").join(', ')}]",
      );
    }

    // Capacity filters
    if (minCapacity != null) {
      filterBy.add('venueInfo.capacity:>=$minCapacity');
    }

    if (maxCapacity != null) {
      filterBy.add('venueInfo.capacity:<=$maxCapacity');
    }

    // Bounding box filter using polygon syntax
    // Create polygon from bounding box coordinates (counter-clockwise order)
    final polygonFilter =
        'location:($swLatitude, $swLongitude, $swLatitude, $neLongitude, $neLatitude, $neLongitude, $neLatitude, $swLongitude)';
    filterBy.add(polygonFilter);

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by':
            'artistName,username,bio,performerInfo.label,venueInfo.type',
        'filter_by': filterBy.join(' && '),
        'per_page': limit,
      };

      final response =
          await client.collection('users').documents.search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final hits = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return _convertTypesenseDocumentToUserModel(document);
          }).toList() ??
          [];

      return hits;
    } catch (e) {
      logger.warning('Typesense bounding box search error: $e');
      return [];
    }
  }

  @override
  Future<List<Booking>> queryBookingsInBoundingBox(
    String input, {
    required double swLatitude,
    required double swLongitude,
    required double neLatitude,
    required double neLongitude,
    int limit = 100,
  }) async {
    // Bounding box filter using polygon syntax
    final polygonFilter =
        'location:($swLatitude, $swLongitude, $swLatitude, $neLongitude, $neLatitude, $neLongitude, $neLatitude, $swLongitude)';

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by': 'title,description',
        'filter_by': polygonFilter,
        'per_page': limit,
      };

      final response = await client
          .collection('bookings')
          .documents
          .search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final results = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return document['id'] as String;
          }).toList() ??
          [];

      final bookingResults = await Future.wait(
        results.map((bookingId) async => _getBooking(bookingId)),
      );

      return bookingResults;
    } catch (e) {
      logger.warning('Typesense bookings bounding box search error: $e');
      return [];
    }
  }

  @override
  Future<List<Opportunity>> queryOpportunitiesInBoundingBox(
    String input, {
    required double swLatitude,
    required double swLongitude,
    required double neLatitude,
    required double neLongitude,
    int limit = 100,
    DateTime? startTime,
  }) async {
    final filterBy = <String>[];

    // Deleted filter
    filterBy.add('deleted:=false');

    // Start time filter
    if (startTime != null) {
      final formattedStartTime = startTime.millisecondsSinceEpoch;
      filterBy.add('startTime:>$formattedStartTime');
    }

    // Bounding box filter using polygon syntax
    final polygonFilter =
        'location:($swLatitude, $swLongitude, $swLatitude, $neLongitude, $neLatitude, $neLongitude, $neLatitude, $swLongitude)';
    filterBy.add(polygonFilter);

    try {
      final searchParameters = <String, dynamic>{
        'q': input.isEmpty ? '*' : input,
        'query_by': 'title,description',
        'filter_by': filterBy.join(' && '),
        'per_page': limit,
      };

      final response = await client
          .collection('opportunities')
          .documents
          .search(searchParameters);

      await _analytics.logSearch(searchTerm: input);

      final results = (response['hits'] as List<dynamic>?)?.map((hit) {
            final document = hit['document'] as Map<String, dynamic>;
            return document['id'] as String;
          }).toList() ??
          [];

      final opportunityResults = await Future.wait(
        results.map((opportunityId) async => _getOpportunity(opportunityId)),
      );

      return opportunityResults;
    } catch (e) {
      logger.warning('Typesense opportunities bounding box search error: $e');
      return [];
    }
  }

  // Helper function to convert Typesense document to UserModel
  UserModel _convertTypesenseDocumentToUserModel(Map<String, dynamic> doc) {
    final tmpTimestamp = doc['timestamp'];
    Timestamp? timestamp;

    if (tmpTimestamp != null) {
      if (tmpTimestamp is int) {
        timestamp = Timestamp.fromMillisecondsSinceEpoch(tmpTimestamp);
      } else if (tmpTimestamp is String) {
        try {
          final dateTime = DateTime.parse(tmpTimestamp);
          timestamp = Timestamp.fromDate(dateTime);
        } catch (e) {
          timestamp = null;
        }
      }
    }

    // Replace timestamp in the document for JSON parsing
    final modifiedDoc = Map<String, dynamic>.from(doc);
    modifiedDoc['timestamp'] = timestamp;

    return UserModel.fromJson(modifiedDoc);
  }
}

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

typedef IdTokenProvider = Future<String?> Function();

class TappedApiClient {
  TappedApiClient({
    Dio? dio,
    IdTokenProvider? idTokenProvider,
    String baseUrl = const String.fromEnvironment(
      'TAPPED_API_URL',
      defaultValue: 'https://api.tapped.ai',
    ),
  })  : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final Dio _dio;
  final IdTokenProvider _idTokenProvider;

  static Future<String?> _firebaseIdToken() async {
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Future<void> createVenueEmailThread({
    required String id,
    required String venueId,
    required String subject,
    required String textBody,
  }) async {
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase authentication is required');
    }

    await _dio.post<void>(
      '/app/v1/venue-email-threads',
      data: {
        'id': id,
        'venue_id': venueId,
        'subject': subject,
        'text_body': textBody,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }
}

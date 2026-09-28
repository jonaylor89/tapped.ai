import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intheloopapp/data/prod/tapped_api_client.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString('', 202);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('creates an authenticated venue email thread', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    final client = TappedApiClient(
      dio: dio,
      idTokenProvider: () async => 'firebase-token',
    );

    await client.createVenueEmailThread(
      id: 'request-1:venue-1',
      venueId: 'venue-1',
      subject: 'Performance inquiry',
      textBody: 'Could we play next Friday?',
    );

    expect(adapter.request?.path, '/app/v1/venue-email-threads');
    expect(
      adapter.request?.headers['Authorization'],
      'Bearer firebase-token',
    );
    expect(adapter.request?.data, {
      'id': 'request-1:venue-1',
      'venue_id': 'venue-1',
      'subject': 'Performance inquiry',
      'text_body': 'Could we play next Friday?',
    });
  });

  test('refuses to send without a Firebase ID token', () async {
    final client = TappedApiClient(
      dio: Dio(BaseOptions(baseUrl: 'https://api.test')),
      idTokenProvider: () async => null,
    );

    await expectLater(
      client.createVenueEmailThread(
        id: 'request-1',
        venueId: 'venue-1',
        subject: 'Inquiry',
        textBody: 'Hello',
      ),
      throwsStateError,
    );
  });
}

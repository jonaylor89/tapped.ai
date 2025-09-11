// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserModelImpl _$$UserModelImplFromJson(Map<String, dynamic> json) =>
    _$UserModelImpl(
      id: json['id'] as String,
      timestamp: const OptionalDateTimeConverter()
          .fromJson(json['timestamp'] as Timestamp?),
      username: const UsernameConverter().fromJson(json['username'] as String),
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] == null
          ? const None()
          : Option<String>.fromJson(
              json['phoneNumber'], (value) => value as String),
      website: json['website'] == null
          ? const None()
          : Option<String>.fromJson(
              json['website'], (value) => value as String),
      unclaimed: json['unclaimed'] as bool? ?? false,
      artistName: json['artistName'] as String? ?? '',
      profilePicture: json['profilePicture'] == null
          ? const None()
          : Option<String>.fromJson(
              json['profilePicture'], (value) => value as String),
      bio: json['bio'] as String? ?? '',
      occupations: (json['occupations'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      location: json['location'] == null
          ? const None()
          : Option<Location>.fromJson(json['location'],
              (value) => Location.fromJson(value as Map<String, dynamic>)),
      badgesCount: (json['badgesCount'] as num?)?.toInt() ?? 0,
      performerInfo: json['performerInfo'] == null
          ? const None()
          : Option<PerformerInfo>.fromJson(json['performerInfo'],
              (value) => PerformerInfo.fromJson(value as Map<String, dynamic>)),
      bookerInfo: json['bookerInfo'] == null
          ? const None()
          : Option<BookerInfo>.fromJson(json['bookerInfo'],
              (value) => BookerInfo.fromJson(value as Map<String, dynamic>)),
      venueInfo: json['venueInfo'] == null
          ? const None()
          : Option<VenueInfo>.fromJson(json['venueInfo'],
              (value) => VenueInfo.fromJson(value as Map<String, dynamic>)),
      socialFollowing: json['socialFollowing'] == null
          ? SocialFollowing.empty
          : SocialFollowing.fromJson(
              json['socialFollowing'] as Map<String, dynamic>),
      emailNotifications: json['emailNotifications'] == null
          ? EmailNotifications.empty
          : EmailNotifications.fromJson(
              json['emailNotifications'] as Map<String, dynamic>),
      pushNotifications: json['pushNotifications'] == null
          ? PushNotifications.empty
          : PushNotifications.fromJson(
              json['pushNotifications'] as Map<String, dynamic>),
      deleted: json['deleted'] as bool? ?? false,
      stripeConnectedAccountId: json['stripeConnectedAccountId'] == null
          ? const None()
          : Option<String>.fromJson(
              json['stripeConnectedAccountId'], (value) => value as String),
      stripeCustomerId: json['stripeCustomerId'] == null
          ? const None()
          : Option<String>.fromJson(
              json['stripeCustomerId'], (value) => value as String),
      latestAppVersion: json['latestAppVersion'] == null
          ? const None()
          : Option<String>.fromJson(
              json['latestAppVersion'], (value) => value as String),
    );

Map<String, dynamic> _$$UserModelImplToJson(_$UserModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'timestamp': const OptionalDateTimeConverter().toJson(instance.timestamp),
      'username': const UsernameConverter().toJson(instance.username),
      'email': instance.email,
      'phoneNumber': instance.phoneNumber.toJson(
        (value) => value,
      ),
      'website': instance.website.toJson(
        (value) => value,
      ),
      'unclaimed': instance.unclaimed,
      'artistName': instance.artistName,
      'profilePicture': instance.profilePicture.toJson(
        (value) => value,
      ),
      'bio': instance.bio,
      'occupations': instance.occupations,
      'location': instance.location.toJson(
        (value) => value.toJson(),
      ),
      'badgesCount': instance.badgesCount,
      'performerInfo': instance.performerInfo.toJson(
        (value) => value.toJson(),
      ),
      'bookerInfo': instance.bookerInfo.toJson(
        (value) => value.toJson(),
      ),
      'venueInfo': instance.venueInfo.toJson(
        (value) => value.toJson(),
      ),
      'socialFollowing': instance.socialFollowing.toJson(),
      'emailNotifications': instance.emailNotifications.toJson(),
      'pushNotifications': instance.pushNotifications.toJson(),
      'deleted': instance.deleted,
      'stripeConnectedAccountId': instance.stripeConnectedAccountId.toJson(
        (value) => value,
      ),
      'stripeCustomerId': instance.stripeCustomerId.toJson(
        (value) => value,
      ),
      'latestAppVersion': instance.latestAppVersion.toJson(
        (value) => value,
      ),
    };

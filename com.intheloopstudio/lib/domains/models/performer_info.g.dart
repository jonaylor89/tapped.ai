// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'performer_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PerformerInfoImpl _$$PerformerInfoImplFromJson(Map<String, dynamic> json) =>
    _$PerformerInfoImpl(
      pressKitUrl: json['pressKitUrl'] == null
          ? const None()
          : Option<String>.fromJson(
              json['pressKitUrl'], (value) => value as String),
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      subgenres: (json['subgenres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      rating: json['rating'] == null
          ? const Option.of(5)
          : Option<double>.fromJson(
              json['rating'], (value) => (value as num).toDouble()),
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      bookingCount: (json['bookingCount'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? 'Independent',
      bookingAgency: json['bookingAgency'] == null
          ? const None()
          : Option<String>.fromJson(
              json['bookingAgency'], (value) => value as String),
      category:
          $enumDecodeNullable(_$PerformerCategoryEnumMap, json['category']) ??
              PerformerCategory.undiscovered,
      averageTicketPrice: json['averageTicketPrice'] == null
          ? const None()
          : Option<int>.fromJson(
              json['averageTicketPrice'], (value) => (value as num).toInt()),
      averageAttendance: json['averageAttendance'] == null
          ? const None()
          : Option<int>.fromJson(
              json['averageAttendance'], (value) => (value as num).toInt()),
      bookingEmail: json['bookingEmail'] == null
          ? const None()
          : Option<String>.fromJson(
              json['bookingEmail'], (value) => value as String),
      chartmetricId: json['chartmetricId'] == null
          ? const None()
          : Option<String>.fromJson(
              json['chartmetricId'], (value) => value as String),
    );

Map<String, dynamic> _$$PerformerInfoImplToJson(_$PerformerInfoImpl instance) =>
    <String, dynamic>{
      'pressKitUrl': instance.pressKitUrl.toJson(
        (value) => value,
      ),
      'genres': instance.genres,
      'subgenres': instance.subgenres,
      'rating': instance.rating.toJson(
        (value) => value,
      ),
      'reviewCount': instance.reviewCount,
      'bookingCount': instance.bookingCount,
      'label': instance.label,
      'bookingAgency': instance.bookingAgency.toJson(
        (value) => value,
      ),
      'category': _$PerformerCategoryEnumMap[instance.category]!,
      'averageTicketPrice': instance.averageTicketPrice.toJson(
        (value) => value,
      ),
      'averageAttendance': instance.averageAttendance.toJson(
        (value) => value,
      ),
      'bookingEmail': instance.bookingEmail.toJson(
        (value) => value,
      ),
      'chartmetricId': instance.chartmetricId.toJson(
        (value) => value,
      ),
    };

const _$PerformerCategoryEnumMap = {
  PerformerCategory.undiscovered: 'undiscovered',
  PerformerCategory.emerging: 'emerging',
  PerformerCategory.hometownHero: 'hometownHero',
  PerformerCategory.mainstream: 'mainstream',
  PerformerCategory.legendary: 'legendary',
};

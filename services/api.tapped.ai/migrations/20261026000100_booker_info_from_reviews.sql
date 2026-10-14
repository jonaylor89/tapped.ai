-- The retired booker-review Function created bookerInfo on a requester's first booker review.
-- Expose booker stats whenever booker reviews exist so venue-only requesters keep their rating.
CREATE OR REPLACE VIEW api_users AS
SELECT u.id, u.profile || jsonb_build_object(
 'id',u.id,'username',u.username,'email',u.email,'artistName',u.artist_name,'bio',u.bio,
 'occupations',u.occupations,'profilePicture',u.profile_picture,'placeId',u.place_id,
 'deleted',u.deleted,'shadowBanned',u.shadow_banned,'unclaimed',u.unclaimed,
 'location',CASE WHEN u.location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(u.location::geometry),'lng',ST_X(u.location::geometry),'placeId',coalesce(u.place_id,'')) END,
 'performerInfo',CASE WHEN u.performer_enabled THEN coalesce(u.profile->'performerInfo','{}') || jsonb_build_object(
 'genres',u.performer_genres,'label',u.performer_label,'rating',s.performer_rating,'reviewCount',s.performer_review_count,
 'bookingCount',s.confirmed_booking_count,'completedBookingCount',s.completed_booking_count) ELSE NULL END,
 'bookerInfo',CASE WHEN u.booker_enabled OR s.booker_review_count > 0 THEN (CASE WHEN jsonb_typeof(u.profile->'bookerInfo')='object' THEN u.profile->'bookerInfo' ELSE '{}' END) || jsonb_build_object('rating',s.booker_rating,'reviewCount',s.booker_review_count) ELSE NULL END,
 'venueInfo',CASE WHEN u.venue_enabled THEN coalesce(u.profile->'venueInfo','{}') || jsonb_build_object(
 'genres',u.venue_genres,'capacity',u.venue_capacity,'type',u.venue_type,'websiteUrl',u.venue_website_url,
 'topPerformerIds',venue_top_performers(u.id),'bookingsByDayOfWeek',venue_booking_days(u.id)) ELSE NULL END
) AS doc FROM users u CROSS JOIN LATERAL (
 SELECT * FROM profile_stats WHERE id=u.id OFFSET 0
) s;

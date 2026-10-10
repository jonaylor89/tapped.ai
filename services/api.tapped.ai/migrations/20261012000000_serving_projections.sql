-- Serving projections merge lossless imported fields with authoritative relational columns.
CREATE VIEW api_users AS SELECT id, profile || jsonb_build_object('id', id, 'username', username, 'email', email, 'artistName', artist_name, 'bio', bio, 'occupations', occupations, 'profilePicture', profile_picture, 'placeId', place_id, 'deleted', deleted, 'shadowBanned', shadow_banned, 'unclaimed', unclaimed, 'location', CASE WHEN location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(location::geometry),'lng',ST_X(location::geometry),'placeId',coalesce(place_id,'')) END) AS doc FROM users;

CREATE VIEW api_services AS SELECT id, profile || jsonb_build_object('id', id, 'userId', user_id, 'title', title, 'description', description, 'rate', rate, 'rateType', rate_type, 'count', count, 'deleted', deleted) AS doc FROM services;

CREATE VIEW api_bookings AS SELECT id, profile || jsonb_build_object('id', id, 'serviceId', service_id, 'addedByUser', added_by_user, 'name', name, 'note', note, 'requesterId', requester_id, 'requesteeId', requestee_id, 'status', status, 'genres', genres, 'rate', rate, 'startTime', start_time, 'endTime', end_time, 'timestamp', occurred_at, 'placeId', place_id, 'ticketsSold', tickets_sold, 'totalEventRevenue', total_event_revenue, 'flierUrl', flier_url, 'eventUrl', event_url, 'referenceEventId', reference_event_id, 'location', CASE WHEN location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(location::geometry),'lng',ST_X(location::geometry),'placeId',coalesce(place_id,'')) END) AS doc FROM bookings;

CREATE VIEW api_activities AS SELECT id, profile || jsonb_build_object('id', id, 'type', activity_type, 'fromUserId', from_user_id, 'toUserId', to_user_id, 'bookingId', booking_id, 'loopId', loop_id, 'commentId', comment_id, 'rootId', root_id, 'count', count, 'markedRead', marked_read, 'timestamp', occurred_at) AS doc FROM activities;

CREATE VIEW api_opportunities AS SELECT id, profile || jsonb_build_object('id', id, 'userId', user_id, 'title', title, 'description', description, 'flierUrl', flier_url, 'placeId', place_id, 'timestamp', occurred_at, 'startTime', start_time, 'endTime', end_time, 'deadline', deadline, 'genres', genres, 'isPaid', is_paid, 'venueId', venue_id, 'referenceEventId', reference_event_id, 'deleted', deleted, 'location', CASE WHEN location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(location::geometry),'lng',ST_X(location::geometry),'placeId',coalesce(place_id,'')) END) AS doc FROM opportunities;

ALTER TABLE reviews DROP CONSTRAINT reviews_pkey;
ALTER TABLE reviews ALTER COLUMN review_type SET NOT NULL;
ALTER TABLE reviews ADD PRIMARY KEY (id,review_type);
CREATE VIEW api_reviews AS SELECT id, review_type, profile || jsonb_build_object('id', id, 'bookerId', booker_id, 'performerId', performer_id, 'bookingId', booking_id, 'timestamp', occurred_at, 'overallRating', overall_rating, 'overallReview', overall_review, 'type', review_type) AS doc FROM reviews;

-- The legacy Flutter review decoder wrote the wrong discriminator. Collection path is authoritative;
-- the importer must set review_type from performerReviews/bookerReviews on the final import.
CREATE TABLE opportunity_dismissals (
 opportunity_id text NOT NULL REFERENCES opportunities(id),
 user_id text NOT NULL REFERENCES users(id),
 PRIMARY KEY(opportunity_id,user_id)
);

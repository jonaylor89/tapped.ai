-- Synthetic local fixtures. Every row is fake; user IDs match platform/local/emulator-seed accounts.
-- Re-running resets all serving tables, so never point this at a shared database.
BEGIN;

TRUNCATE users, services, bookings, activities, device_tokens, api_keys, opportunities,
    opportunity_interested_users, opportunity_dismissals, reviews;

INSERT INTO users (id, username, email, artist_name, bio, occupations, location, place_id, profile) VALUES
('local-alice', 'alice_local', 'alice@example.test', 'Alice Local', 'Synthetic indie songwriter for local E2E.',
    '{singer,guitarist}', ST_SetSRID(ST_MakePoint(-73.9571, 40.7178), 4326)::geography, 'local-place-williamsburg',
    '{"performerInfo": {"genres": ["indie", "folk"], "label": "Independent", "rating": 4.5, "reviewCount": 1}}'),
('local-bluebird', 'bluebird_local', 'venue@example.test', 'Bluebird Room (Local)', 'Synthetic 120-cap venue.',
    '{venue}', ST_SetSRID(ST_MakePoint(-73.9442, 40.7081), 4326)::geography, 'local-place-bushwick',
    '{"venueInfo": {"type": "bar", "capacity": 120, "genres": ["indie", "rock"]}}'),
('local-carol', 'carol_local', 'carol@example.test', 'Carol Booker', 'Synthetic booker.',
    '{booker}', ST_SetSRID(ST_MakePoint(-73.9903, 40.7359), 4326)::geography, 'local-place-union-square',
    '{"bookerInfo": {"rating": 5, "reviewCount": 0}}');

-- Unclaimed venue: performers contacting it get an AI-composed email (OpenAI stub -> Mailpit).
INSERT INTO users (id, username, email, artist_name, bio, occupations, location, place_id, unclaimed,
    profile) VALUES
('local-capital', 'capital_local', 'capital@example.test', 'Capital Ale House (Local)', 'Synthetic unclaimed venue.',
    '{venue}', ST_SetSRID(ST_MakePoint(-73.9500, 40.7100), 4326)::geography, 'local-place-capital', true,
    '{"venueInfo": {"type": "bar", "capacity": 200, "bookingEmail": "booking@capital.example.test"}}');

INSERT INTO services (id, user_id, title, description, rate, rate_type, count) VALUES
('local-service-alice-set', 'local-alice', 'Acoustic set', '45 minute acoustic set.', 300, 'fixed', 1);

INSERT INTO opportunities (id, user_id, title, description, location, place_id, occurred_at, start_time,
    end_time, deadline, genres, is_paid, venue_id) VALUES
('local-opp-friday', 'local-bluebird', 'Friday indie night', 'Looking for an opener.',
    ST_SetSRID(ST_MakePoint(-73.9442, 40.7081), 4326)::geography, 'local-place-bushwick', now(),
    now() + interval '7 days', now() + interval '7 days 3 hours', now() + interval '5 days',
    '{indie}', true, 'local-bluebird'),
('local-opp-sunday', 'local-bluebird', 'Sunday folk brunch', 'Already has one applicant.',
    ST_SetSRID(ST_MakePoint(-73.9442, 40.7081), 4326)::geography, 'local-place-bushwick', now(),
    now() + interval '9 days', now() + interval '9 days 2 hours', now() + interval '8 days',
    '{folk}', false, 'local-bluebird'),
('local-opp-capital', 'local-capital', 'Saturday rock night', 'Listed from a past show.',
    ST_SetSRID(ST_MakePoint(-73.9500, 40.7100), 4326)::geography, 'local-place-capital', now(),
    now() + interval '12 days', now() + interval '12 days 3 hours', now() + interval '10 days',
    '{rock}', true, 'local-capital');

UPDATE opportunities SET reference_event_id = 'local-event-capital' WHERE id = 'local-opp-capital';

INSERT INTO opportunity_interested_users (opportunity_id, user_id) VALUES
('local-opp-sunday', 'local-alice');

INSERT INTO bookings (id, service_id, name, note, requester_id, requestee_id, status, genres, rate,
    start_time, end_time, occurred_at, location, place_id) VALUES
('local-booking-past', 'local-service-alice-set', 'Rooftop party', 'Completed gig.', 'local-carol',
    'local-alice', 'confirmed', '{indie}', 300, now() - interval '14 days',
    now() - interval '14 days' + interval '1 hour', now() - interval '20 days',
    ST_SetSRID(ST_MakePoint(-73.9903, 40.7359), 4326)::geography, 'local-place-union-square'),
('local-booking-pending', 'local-service-alice-set', 'Gallery opening', 'Awaiting Alice.', 'local-carol',
    'local-alice', 'pending', '{folk}', 300, now() + interval '10 days',
    now() + interval '10 days' + interval '1 hour', now() - interval '1 day',
    ST_SetSRID(ST_MakePoint(-73.9903, 40.7359), 4326)::geography, 'local-place-union-square'),
('local-booking-capital', 'local-service-alice-set', 'Capital past show', 'Seeds the venue outreach link.',
    'local-capital', 'local-alice', 'confirmed', '{rock}', 300, now() - interval '30 days',
    now() - interval '30 days' + interval '1 hour', now() - interval '40 days',
    ST_SetSRID(ST_MakePoint(-73.9500, 40.7100), 4326)::geography, 'local-place-capital');

UPDATE bookings SET reference_event_id = 'local-event-capital' WHERE id = 'local-booking-capital';

INSERT INTO reviews (id, booker_id, performer_id, booking_id, occurred_at, overall_rating, overall_review,
    review_type, reviewee_id) VALUES
('local-review-past', 'local-carol', 'local-alice', 'local-booking-past', now() - interval '13 days', 4.5,
    'Great synthetic set.', 'performer', 'local-alice');

INSERT INTO activities (id, activity_type, from_user_id, to_user_id, booking_id, occurred_at, profile) VALUES
('local-activity-request', 'bookingRequest', 'local-carol', 'local-alice', 'local-booking-pending',
    now() - interval '1 day', '{"status": "pending"}');

COMMIT;

-- Canonical profiles are distinct from authenticated accounts. Preserve legacy IDs/API shapes.
CREATE TABLE accounts (
  auth_uid text PRIMARY KEY,
  disabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO accounts(auth_uid,disabled) SELECT uid,deleted FROM firebase_identities;
CREATE TABLE profile_owners (
  profile_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  auth_uid text NOT NULL REFERENCES accounts(auth_uid) ON DELETE CASCADE,
  PRIMARY KEY(profile_id,auth_uid)
);
CREATE INDEX profile_owners_account_idx ON profile_owners(auth_uid);
INSERT INTO profile_owners SELECT u.id,a.auth_uid FROM users u JOIN accounts a ON a.auth_uid=u.id
WHERE NOT u.unclaimed AND NOT u.deleted AND NOT a.disabled;

-- Private archival provenance; never part of client views. No source Firestore writes/deletes.
CREATE TABLE legacy_profile_archive AS SELECT id AS profile_id, profile FROM users;
ALTER TABLE legacy_profile_archive ADD PRIMARY KEY(profile_id);
CREATE TABLE legacy_invalid_records (
  entity_type text NOT NULL, entity_id text NOT NULL, original_record jsonb NOT NULL,
  PRIMARY KEY(entity_type,entity_id)
);

ALTER TABLE users
  ADD COLUMN performer_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN performer_genres text[] NOT NULL DEFAULT '{}',
  ADD COLUMN performer_label text NOT NULL DEFAULT '',
  ADD COLUMN venue_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN venue_genres text[] NOT NULL DEFAULT '{}',
  ADD COLUMN venue_capacity integer CHECK (venue_capacity >= 0),
  ADD COLUMN venue_type text NOT NULL DEFAULT '',
  ADD COLUMN venue_website_url text,
  ADD COLUMN booker_enabled boolean NOT NULL DEFAULT false;

CREATE FUNCTION profile_string_array(value jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(x #>> '{}' ORDER BY ordinal),'{}'::text[])
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(value)='array' THEN value ELSE '[]'::jsonb END)
    WITH ORDINALITY e(x,ordinal) WHERE jsonb_typeof(x)='string'
$$;
CREATE FUNCTION normalize_profile_fields() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE section jsonb;
BEGIN
  IF NEW.profile ? 'performerInfo' THEN
    section := NEW.profile->'performerInfo';
    NEW.performer_enabled := jsonb_typeof(section)='object';
    IF NEW.performer_enabled THEN
      IF section ? 'genres' THEN NEW.performer_genres := profile_string_array(section->'genres'); END IF;
      IF section ? 'label' THEN NEW.performer_label := coalesce(section->>'label',''); END IF;
      NEW.profile := jsonb_set(NEW.profile,'{performerInfo}',section - ARRAY['genres','label','rating','reviewCount','bookingCount','completedBookingCount']);
    ELSE NEW.performer_enabled := false; NEW.performer_genres := '{}'; NEW.performer_label := ''; END IF;
  END IF;
  IF NEW.profile ? 'venueInfo' THEN
    section := NEW.profile->'venueInfo';
    NEW.venue_enabled := jsonb_typeof(section)='object';
    IF NEW.venue_enabled THEN
      IF section ? 'genres' THEN NEW.venue_genres := profile_string_array(section->'genres'); END IF;
      IF section ? 'type' THEN NEW.venue_type := coalesce(section->>'type',''); END IF;
      IF section ? 'websiteUrl' THEN NEW.venue_website_url := section->>'websiteUrl'; END IF;
      IF section ? 'capacity' THEN
        NEW.venue_capacity := CASE WHEN section->>'capacity' ~ '^[0-9]{1,9}$' THEN (section->>'capacity')::integer ELSE NULL END;
      END IF;
      NEW.profile := jsonb_set(NEW.profile,'{venueInfo}',section - ARRAY['genres','type','websiteUrl','capacity','topPerformerIds','bookingsByDayOfWeek']);
    ELSE NEW.venue_enabled := false; NEW.venue_genres := '{}'; NEW.venue_capacity := NULL; NEW.venue_type := ''; NEW.venue_website_url := NULL; END IF;
  END IF;
  IF NEW.profile ? 'bookerInfo' THEN
    section := NEW.profile->'bookerInfo';
    NEW.booker_enabled := jsonb_typeof(section)='object';
    IF NEW.booker_enabled THEN NEW.profile := jsonb_set(NEW.profile,'{bookerInfo}',section - ARRAY['rating','reviewCount','bookingCount']);
    ELSE NEW.booker_enabled := false; END IF;
  END IF;
  -- A missing/null role is false, never a nullable boolean.
  NEW.performer_enabled := coalesce(NEW.performer_enabled,false);
  NEW.venue_enabled := coalesce(NEW.venue_enabled,false);
  NEW.booker_enabled := coalesce(NEW.booker_enabled,false);
  RETURN NEW;
END $$;
CREATE TRIGGER users_normalize_profile BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION normalize_profile_fields();
UPDATE users SET profile=profile;
CREATE FUNCTION normalized_search_terms(terms text[]) RETURNS text[] LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT coalesce(array_agg(lower(v)),'{}'::text[]) FROM unnest(terms) v $$;
CREATE INDEX users_occupations_search_idx ON users USING gin(normalized_search_terms(occupations)) WHERE NOT deleted AND NOT shadow_banned;
CREATE INDEX users_performer_genres_idx ON users USING gin(performer_genres) WHERE NOT deleted AND NOT shadow_banned;
CREATE INDEX users_venue_genres_idx ON users USING gin(venue_genres) WHERE NOT deleted AND NOT shadow_banned;
CREATE INDEX users_venue_capacity_idx ON users(venue_capacity) WHERE NOT deleted AND NOT shadow_banned;
DROP INDEX users_search_text_idx;
CREATE INDEX users_search_text_idx ON users USING gin(
 (lower(artist_name || ' ' || username || ' ' || bio || ' ' || performer_label || ' ' || venue_type)) gin_trgm_ops
) WHERE NOT deleted AND NOT shadow_banned;

-- Scraped events/provenance are not accounts and do not generate app notifications.
CREATE TABLE scraped_events (
  source text NOT NULL, source_key text NOT NULL, venue_id text NOT NULL REFERENCES users(id),
  event_id text NOT NULL UNIQUE, payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(source,source_key)
);
CREATE INDEX scraped_events_venue_idx ON scraped_events(venue_id);
CREATE TABLE scrape_runs (
  id text PRIMARY KEY, scraper_id text NOT NULL REFERENCES users(id),
  started_at timestamptz NOT NULL DEFAULT now(), ended_at timestamptz, error text,
  CHECK(ended_at IS NULL OR ended_at>=started_at)
);

-- Preserve orphan identities as explicitly hidden, unclaimed historical reference stubs.
-- They are not Firebase users, never acquire an account or owner, and emit no outbox effects.
DO $$
DECLARE ref record;
BEGIN
 FOR ref IN SELECT * FROM (VALUES
  ('services','user_id'),('bookings','requester_id'),('bookings','requestee_id'),
  ('activities','from_user_id'),('activities','to_user_id'),('opportunities','user_id'),
  ('opportunities','venue_id'),('reviews','booker_id'),('reviews','performer_id'),
  ('reviews','reviewee_id'),
  ('opportunity_interested_users','user_id')) AS refs(tbl,col)
 LOOP
  EXECUTE format('INSERT INTO users(id,unclaimed,deleted,profile) SELECT DISTINCT t.%I,true,true,''{"legacyReferenceStub":true}''::jsonb FROM %I t LEFT JOIN users u ON u.id=t.%I WHERE t.%I IS NOT NULL AND u.id IS NULL ON CONFLICT DO NOTHING',ref.col,ref.tbl,ref.col,ref.col);
 END LOOP;
END $$;
INSERT INTO services(id,deleted,profile)
SELECT DISTINCT b.service_id,true,'{"legacyReferenceStub":true}'::jsonb FROM bookings b LEFT JOIN services s ON s.id=b.service_id
WHERE b.service_id IS NOT NULL AND s.id IS NULL;
INSERT INTO bookings(id,status,profile)
SELECT DISTINCT r.booking_id,'canceled','{"legacyReferenceStub":true}'::jsonb FROM reviews r LEFT JOIN bookings b ON b.id=r.booking_id
WHERE r.booking_id IS NOT NULL AND b.id IS NULL;
INSERT INTO bookings(id,status,profile)
SELECT DISTINCT a.booking_id,'canceled','{"legacyReferenceStub":true}'::jsonb FROM activities a LEFT JOIN bookings b ON b.id=a.booking_id WHERE a.booking_id IS NOT NULL AND b.id IS NULL;
INSERT INTO opportunities(id,deleted,profile)
SELECT DISTINCT i.opportunity_id,true,'{"legacyReferenceStub":true}'::jsonb FROM opportunity_interested_users i LEFT JOIN opportunities o ON o.id=i.opportunity_id WHERE o.id IS NULL;

INSERT INTO legacy_invalid_records SELECT 'booking',id,to_jsonb(b) FROM bookings b WHERE status NOT IN ('pending','confirmed','canceled');
UPDATE bookings SET status='canceled' WHERE status NOT IN ('pending','confirmed','canceled');
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check CHECK(status IN ('pending','confirmed','canceled'));
ALTER TABLE bookings ADD CONSTRAINT bookings_time_order CHECK(start_time IS NULL OR end_time IS NULL OR start_time<=end_time) NOT VALID;
-- Invalid imported time ranges remain archived; null canonical times cannot schedule reminders.
INSERT INTO legacy_invalid_records SELECT 'booking_time',id,to_jsonb(b) FROM bookings b WHERE start_time>end_time;
UPDATE bookings SET start_time=NULL,end_time=NULL WHERE start_time>end_time;
ALTER TABLE bookings VALIDATE CONSTRAINT bookings_time_order;
INSERT INTO legacy_invalid_records SELECT 'review_rating',id||':'||review_type||':'||reviewee_id,to_jsonb(r) FROM reviews r WHERE NOT(overall_rating BETWEEN 0 AND 5);
UPDATE reviews SET overall_rating=NULL WHERE NOT(overall_rating BETWEEN 0 AND 5);
ALTER TABLE reviews ADD CONSTRAINT reviews_rating_check CHECK(overall_rating BETWEEN 0 AND 5);
ALTER TABLE reviews ADD COLUMN legacy_duplicate boolean NOT NULL DEFAULT false;
WITH ranked AS (SELECT id,review_type,reviewee_id,row_number() OVER(PARTITION BY booking_id,review_type ORDER BY occurred_at DESC NULLS LAST,id) AS n FROM reviews WHERE booking_id IS NOT NULL)
UPDATE reviews r SET legacy_duplicate=true FROM ranked d WHERE r.id=d.id AND r.review_type=d.review_type AND r.reviewee_id=d.reviewee_id AND d.n>1;
CREATE UNIQUE INDEX reviews_one_per_booking_role ON reviews(booking_id,review_type) WHERE booking_id IS NOT NULL AND NOT legacy_duplicate;
ALTER TABLE reviews ADD CONSTRAINT reviews_type_check CHECK(review_type IN ('performer','booker'));
DO $$
DECLARE ref record;
BEGIN
 FOR ref IN SELECT * FROM (VALUES
 ('services','user_id','users'),('bookings','requester_id','users'),('bookings','requestee_id','users'),('bookings','service_id','services'),
 ('activities','from_user_id','users'),('activities','to_user_id','users'),('activities','booking_id','bookings'),
 ('opportunities','user_id','users'),('opportunities','venue_id','users'),
 ('reviews','booker_id','users'),('reviews','performer_id','users'),('reviews','reviewee_id','users'),('reviews','booking_id','bookings'),

 ('opportunity_interested_users','user_id','users'),('opportunity_interested_users','opportunity_id','opportunities')) AS refs(tbl,col,target)
 LOOP
  EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY(%I) REFERENCES %I(id) DEFERRABLE INITIALLY IMMEDIATE',ref.tbl,ref.tbl||'_'||ref.col||'_fk',ref.col,ref.target);
 END LOOP;
END $$;

INSERT INTO accounts(auth_uid,disabled) SELECT user_id,true FROM device_tokens UNION SELECT user_id,true FROM api_keys ON CONFLICT DO NOTHING;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_account_fk FOREIGN KEY(user_id) REFERENCES accounts(auth_uid);
ALTER TABLE api_keys ADD CONSTRAINT api_keys_account_fk FOREIGN KEY(user_id) REFERENCES accounts(auth_uid);

CREATE INDEX bookings_confirmed_performer_idx ON bookings(requestee_id,end_time) WHERE status='confirmed';
CREATE INDEX bookings_confirmed_venue_idx ON bookings(requester_id,start_time,requestee_id) WHERE status='confirmed';
CREATE INDEX bookings_confirmed_service_idx ON bookings(service_id) WHERE status='confirmed';
-- The retained services.count column is historical import provenance, never read or written by clients.
CREATE OR REPLACE VIEW api_services AS SELECT s.id,s.profile || jsonb_build_object('id',s.id,'userId',s.user_id,'title',s.title,'description',s.description,'rate',s.rate,'rateType',s.rate_type,'count',(SELECT count(*) FROM bookings b WHERE b.service_id=s.id AND b.status='confirmed'),'deleted',s.deleted) AS doc FROM services s;
CREATE OR REPLACE VIEW api_reviews AS SELECT id,review_type,profile || jsonb_build_object('id',id,'bookerId',booker_id,'performerId',performer_id,'bookingId',booking_id,'timestamp',occurred_at,'overallRating',overall_rating,'overallReview',overall_review,'type',review_type) AS doc,reviewee_id FROM reviews WHERE NOT legacy_duplicate;
CREATE INDEX reviews_stats_idx ON reviews(reviewee_id,review_type) INCLUDE(overall_rating) WHERE NOT legacy_duplicate;

-- Read models, not stored counters. Confirmed includes future bookings; completed requires end_time.
CREATE VIEW profile_stats AS
SELECT u.id,
 b.confirmed_booking_count,b.completed_booking_count,
 r.performer_review_count,r.performer_rating,r.booker_review_count,r.booker_rating
FROM users u
CROSS JOIN LATERAL (
 SELECT count(*) AS confirmed_booking_count,count(*) FILTER(WHERE end_time<=now()) AS completed_booking_count
 FROM bookings WHERE requestee_id=u.id AND status='confirmed'
) b
CROSS JOIN LATERAL (
 SELECT count(*) FILTER(WHERE review_type='performer') AS performer_review_count,
 avg(overall_rating) FILTER(WHERE review_type='performer') AS performer_rating,
 count(*) FILTER(WHERE review_type='booker') AS booker_review_count,
 avg(overall_rating) FILTER(WHERE review_type='booker') AS booker_rating
 FROM reviews WHERE reviewee_id=u.id AND NOT legacy_duplicate
) r;
CREATE FUNCTION venue_top_performers(venue text, max_results integer DEFAULT 5) RETURNS text[] LANGUAGE sql STABLE AS $$
 SELECT coalesce(array_agg(id ORDER BY total DESC,id),'{}'::text[]) FROM (
 SELECT b.requestee_id AS id,count(*) AS total FROM bookings b JOIN users p ON p.id=b.requestee_id
 WHERE b.requester_id=venue AND b.status='confirmed' AND NOT p.deleted AND NOT p.shadow_banned
 GROUP BY b.requestee_id ORDER BY total DESC,b.requestee_id LIMIT greatest(0,least(max_results,20))) ranked
$$;
CREATE FUNCTION venue_booking_days(venue text) RETURNS bigint[] LANGUAGE sql STABLE AS $$
 SELECT array_agg(coalesce(total,0) ORDER BY day) FROM generate_series(0,6) d(day)
 LEFT JOIN (SELECT extract(dow FROM start_time AT TIME ZONE 'UTC')::integer AS day,count(*) AS total
 FROM bookings WHERE requester_id=venue AND status='confirmed' AND start_time IS NOT NULL GROUP BY 1) counts USING(day)
$$;
CREATE OR REPLACE VIEW api_users AS
SELECT u.id, u.profile || jsonb_build_object(
 'id',u.id,'username',u.username,'email',u.email,'artistName',u.artist_name,'bio',u.bio,
 'occupations',u.occupations,'profilePicture',u.profile_picture,'placeId',u.place_id,
 'deleted',u.deleted,'shadowBanned',u.shadow_banned,'unclaimed',u.unclaimed,
 'location',CASE WHEN u.location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(u.location::geometry),'lng',ST_X(u.location::geometry),'placeId',coalesce(u.place_id,'')) END,
 'performerInfo',CASE WHEN u.performer_enabled THEN coalesce(u.profile->'performerInfo','{}') || jsonb_build_object(
 'genres',u.performer_genres,'label',u.performer_label,'rating',s.performer_rating,'reviewCount',s.performer_review_count,
 'bookingCount',s.confirmed_booking_count,'completedBookingCount',s.completed_booking_count) ELSE NULL END,
 'bookerInfo',CASE WHEN u.booker_enabled THEN coalesce(u.profile->'bookerInfo','{}') || jsonb_build_object('rating',s.booker_rating,'reviewCount',s.booker_review_count) ELSE NULL END,
 'venueInfo',CASE WHEN u.venue_enabled THEN coalesce(u.profile->'venueInfo','{}') || jsonb_build_object(
 'genres',u.venue_genres,'capacity',u.venue_capacity,'type',u.venue_type,'websiteUrl',u.venue_website_url,
 'topPerformerIds',venue_top_performers(u.id),'bookingsByDayOfWeek',venue_booking_days(u.id)) ELSE NULL END
) AS doc FROM users u JOIN profile_stats s USING(id);

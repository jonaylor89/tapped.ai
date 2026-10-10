-- Normalized fields support the API's current access patterns. Any Firestore-only fields are
-- retained in `profile` so the import remains lossless while the Postgres model evolves.
CREATE TABLE services (
    id          text PRIMARY KEY,
    user_id     text,
    title       text NOT NULL DEFAULT '',
    description text NOT NULL DEFAULT '',
    rate        numeric NOT NULL DEFAULT 0,
    rate_type   text,
    count       integer NOT NULL DEFAULT 0,
    deleted     boolean NOT NULL DEFAULT false,
    profile     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX services_user_id_idx ON services (user_id) WHERE user_id IS NOT NULL;
CREATE TRIGGER services_set_updated_at BEFORE UPDATE ON services
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE bookings (
    id                  text PRIMARY KEY,
    service_id          text,
    added_by_user       boolean NOT NULL DEFAULT false,
    name                text NOT NULL DEFAULT '',
    note                text NOT NULL DEFAULT '',
    requester_id        text,
    requestee_id        text,
    status              text NOT NULL DEFAULT 'confirmed',
    genres              text[] NOT NULL DEFAULT '{}',
    rate                numeric NOT NULL DEFAULT 0,
    start_time          timestamptz,
    end_time            timestamptz,
    occurred_at         timestamptz,
    location            geography(Point, 4326),
    place_id            text,
    tickets_sold        integer,
    total_event_revenue numeric,
    flier_url           text,
    event_url           text,
    reference_event_id  text,
    profile             jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX bookings_service_id_idx ON bookings (service_id) WHERE service_id IS NOT NULL;
CREATE INDEX bookings_requester_status_idx ON bookings (requester_id, status) WHERE requester_id IS NOT NULL;
CREATE INDEX bookings_requestee_status_idx ON bookings (requestee_id, status) WHERE requestee_id IS NOT NULL;
CREATE INDEX bookings_reference_event_id_idx ON bookings (reference_event_id) WHERE reference_event_id IS NOT NULL;
CREATE INDEX bookings_start_time_idx ON bookings (start_time) WHERE start_time IS NOT NULL;
CREATE INDEX bookings_location_idx ON bookings USING gist (location);
CREATE TRIGGER bookings_set_updated_at BEFORE UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE activities (
    id           text PRIMARY KEY,
    activity_type text NOT NULL DEFAULT '',
    from_user_id text,
    to_user_id   text,
    booking_id   text,
    loop_id      text,
    comment_id   text,
    root_id      text,
    count        integer NOT NULL DEFAULT 0,
    marked_read  boolean NOT NULL DEFAULT false,
    occurred_at  timestamptz,
    profile      jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX activities_to_user_read_time_idx ON activities (to_user_id, marked_read, occurred_at DESC)
    WHERE to_user_id IS NOT NULL;
CREATE INDEX activities_from_user_time_idx ON activities (from_user_id, occurred_at DESC)
    WHERE from_user_id IS NOT NULL;
CREATE INDEX activities_booking_id_idx ON activities (booking_id) WHERE booking_id IS NOT NULL;
CREATE TRIGGER activities_set_updated_at BEFORE UPDATE ON activities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE device_tokens (
    token       text PRIMARY KEY,
    user_id     text NOT NULL,
    platform    text,
    profile     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX device_tokens_user_id_idx ON device_tokens (user_id);
CREATE TRIGGER device_tokens_set_updated_at BEFORE UPDATE ON device_tokens
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- API keys are credentials. Only a SHA-256 digest is retained in Postgres; the raw key is never
-- placed in `profile` or in any column.
CREATE TABLE api_keys (
    key_hash    char(64) PRIMARY KEY CHECK (key_hash ~ '^[0-9a-f]{64}$'),
    user_id     text NOT NULL,
    profile     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX api_keys_user_id_idx ON api_keys (user_id);
CREATE TRIGGER api_keys_set_updated_at BEFORE UPDATE ON api_keys
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

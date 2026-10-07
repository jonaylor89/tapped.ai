CREATE EXTENSION IF NOT EXISTS postgis;

CREATE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Mirrors Firestore `users/{uid}`. Columns are the fields the API filters, sorts, or searches on;
-- everything else (performerInfo, venueInfo, bookerInfo, socialFollowing, notification settings,
-- ...) stays in `profile` under its Firestore name until something needs it as a column.
CREATE TABLE users (
    id              text PRIMARY KEY,           -- Firebase Auth UID
    username        text NOT NULL DEFAULT '',
    email           text NOT NULL DEFAULT '',
    artist_name     text NOT NULL DEFAULT '',
    bio             text NOT NULL DEFAULT '',
    occupations     text[] NOT NULL DEFAULT '{}',
    profile_picture text,
    location        geography(Point, 4326),
    place_id        text,
    deleted         boolean NOT NULL DEFAULT false,
    shadow_banned   boolean NOT NULL DEFAULT false,
    unclaimed       boolean NOT NULL DEFAULT false,
    profile         jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Not unique yet: Firestore never enforced it. Make it unique once imported data is deduplicated.
CREATE INDEX users_username_idx ON users (lower(username));
CREATE INDEX users_location_idx ON users USING gist (location);
CREATE INDEX users_updated_at_idx ON users (updated_at);

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

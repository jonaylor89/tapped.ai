CREATE TABLE opportunities (
    id                  text PRIMARY KEY,
    user_id             text,
    title               text NOT NULL DEFAULT '',
    description         text NOT NULL DEFAULT '',
    flier_url           text,
    location            geography(Point, 4326),
    place_id            text,
    occurred_at         timestamptz,
    start_time          timestamptz,
    end_time            timestamptz,
    deadline            timestamptz,
    genres              text[] NOT NULL DEFAULT '{}',
    is_paid             boolean NOT NULL DEFAULT false,
    venue_id            text,
    reference_event_id  text,
    deleted             boolean NOT NULL DEFAULT false,
    profile             jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX opportunities_user_id_idx ON opportunities (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX opportunities_start_time_idx ON opportunities (start_time) WHERE start_time IS NOT NULL;
CREATE INDEX opportunities_location_idx ON opportunities USING gist (location);
CREATE TRIGGER opportunities_set_updated_at BEFORE UPDATE ON opportunities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE opportunity_interested_users (
    opportunity_id text NOT NULL,
    user_id        text NOT NULL,
    profile        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (opportunity_id, user_id)
);
CREATE INDEX opportunity_interested_users_user_id_idx ON opportunity_interested_users (user_id);
CREATE TRIGGER opportunity_interested_users_set_updated_at BEFORE UPDATE ON opportunity_interested_users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE reviews (
    id             text PRIMARY KEY,
    booker_id      text,
    performer_id   text,
    booking_id     text,
    occurred_at    timestamptz,
    overall_rating double precision,
    overall_review text NOT NULL DEFAULT '',
    review_type    text,
    profile        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reviews_performer_time_idx ON reviews (performer_id, occurred_at DESC) WHERE performer_id IS NOT NULL;
CREATE INDEX reviews_booker_time_idx ON reviews (booker_id, occurred_at DESC) WHERE booker_id IS NOT NULL;
CREATE INDEX reviews_booking_id_idx ON reviews (booking_id) WHERE booking_id IS NOT NULL;
CREATE TRIGGER reviews_set_updated_at BEFORE UPDATE ON reviews
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

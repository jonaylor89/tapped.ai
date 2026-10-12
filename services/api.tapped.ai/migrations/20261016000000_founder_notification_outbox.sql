-- Application mutations and their founder notifications commit atomically.
-- No historical backfill: imported rows must not replay old notifications.
CREATE TABLE founder_notification_outbox (
    event_id text PRIMARY KEY,
    event_type text NOT NULL CHECK (event_type IN ('onboarding', 'booking', 'opportunity_interest')),
    subject_id text NOT NULL,
    actor_id text NOT NULL,
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    available_at timestamptz NOT NULL DEFAULT now(),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    lease_token text,
    locked_until timestamptz,
    delivered_at timestamptz,
    last_error text,
    CHECK ((lease_token IS NULL) = (locked_until IS NULL))
);

CREATE INDEX founder_notification_outbox_pending
    ON founder_notification_outbox (available_at, created_at)
    WHERE delivered_at IS NULL;

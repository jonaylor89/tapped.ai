-- Internal deliveries only. No API exposes these payloads or credentials.
CREATE TABLE external_effect_outbox (
 id text PRIMARY KEY,
 kind text NOT NULL CHECK (kind IN ('auth_signup','auth_delete','stream_profile','push','mail')),
 payload jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 available_at timestamptz NOT NULL DEFAULT now(),
 attempts integer NOT NULL DEFAULT 0,
 lock_token uuid,
 locked_until timestamptz,
 delivered_at timestamptz,
 last_error text
);
CREATE INDEX external_effect_pending ON external_effect_outbox(available_at,created_at) WHERE delivered_at IS NULL;
CREATE TABLE email_templates (
 name text PRIMARY KEY,
 subject text NOT NULL,
 text_body text NOT NULL DEFAULT '',
 html_body text
);
CREATE TABLE firebase_identity_sync (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 baseline_started_at timestamptz NOT NULL DEFAULT now(),
 baseline_completed_at timestamptz,
 completed_scan_at timestamptz
);
CREATE TABLE firebase_identities (
 uid text PRIMARY KEY,
 email text NOT NULL DEFAULT '',
 display_name text NOT NULL DEFAULT '',
 created_at_ms bigint NOT NULL,
 scan_id uuid NOT NULL,
 deleted boolean NOT NULL DEFAULT false
);
ALTER TABLE founder_notification_outbox DROP CONSTRAINT founder_notification_outbox_event_type_check;
ALTER TABLE founder_notification_outbox ADD CONSTRAINT founder_notification_outbox_event_type_check
 CHECK (event_type IN ('onboarding','booking','opportunity_interest','auth_signup','auth_delete','feedback','orphan_mail'));

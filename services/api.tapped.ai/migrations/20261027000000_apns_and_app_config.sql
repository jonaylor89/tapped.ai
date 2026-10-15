-- iOS builds without FirebaseMessaging register raw APNs device tokens. Existing rows and older
-- builds keep FCM until those builds age out; delivery picks the transport per token.
ALTER TABLE device_tokens
  ADD COLUMN provider text NOT NULL DEFAULT 'fcm' CHECK (provider IN ('fcm','apns')),
  ADD COLUMN apns_environment text CHECK (apns_environment IN ('development','production')),
  ADD CONSTRAINT device_tokens_apns_environment CHECK ((provider='apns') = (apns_environment IS NOT NULL));

-- Launch gates previously served by Firebase Remote Config. One row; edit it with SQL.
-- Seeded with the in-app defaults: the Remote Config template held no parameters at retirement.
CREATE TABLE app_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  down_for_maintenance boolean NOT NULL DEFAULT false,
  booking_fee double precision NOT NULL DEFAULT 0,
  ios_minimum_app_version text NOT NULL DEFAULT '',
  ios_latest_app_version text NOT NULL DEFAULT '',
  premium_waitlist_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app_config DEFAULT VALUES;
CREATE TRIGGER app_config_set_updated_at BEFORE UPDATE ON app_config
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

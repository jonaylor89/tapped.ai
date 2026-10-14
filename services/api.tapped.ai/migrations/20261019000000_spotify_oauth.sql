-- OAuth secrets and one-time PKCE state: never exposed by application collection APIs.
CREATE TABLE spotify_oauth_states (
 state_hash char(64) PRIMARY KEY,
 user_id text NOT NULL,
 verifier text NOT NULL,
 redirect_uri text NOT NULL,
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz
);
CREATE INDEX spotify_oauth_state_expiry ON spotify_oauth_states(expires_at);
CREATE TABLE spotify_oauth_tokens (
 user_id text PRIMARY KEY,
 access_token text NOT NULL,
 refresh_token text NOT NULL,
 token_type text NOT NULL,
 scope text NOT NULL,
 expires_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);

-- OAuth 2.1 for the MCP server (/mcp). Clients register dynamically; users sign in with Firebase
-- on app.tapped.ai and approve. Codes and tokens are stored only as SHA-256 hashes.
CREATE TABLE mcp_clients (
    id text PRIMARY KEY,
    name text NOT NULL,
    redirect_uris text[] NOT NULL CHECK (cardinality(redirect_uris) BETWEEN 1 AND 10),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- A pending authorization; approval attaches the user and a single-use code.
CREATE TABLE mcp_authorization_requests (
    id text PRIMARY KEY,
    client_id text NOT NULL REFERENCES mcp_clients (id) ON DELETE CASCADE,
    redirect_uri text NOT NULL,
    code_challenge text NOT NULL,
    state text,
    expires_at timestamptz NOT NULL,
    user_id text,
    code_hash text UNIQUE,
    CHECK ((user_id IS NULL) = (code_hash IS NULL))
);

CREATE INDEX mcp_authorization_requests_expiry ON mcp_authorization_requests (expires_at);

-- One per approved connection; revoking it revokes all of its tokens.
CREATE TABLE mcp_grants (
    id uuid PRIMARY KEY,
    client_id text NOT NULL REFERENCES mcp_clients (id) ON DELETE CASCADE,
    user_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz
);

CREATE INDEX mcp_grants_user ON mcp_grants (user_id);

CREATE TABLE mcp_tokens (
    hash text PRIMARY KEY,
    grant_id uuid NOT NULL REFERENCES mcp_grants (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('access', 'refresh')),
    expires_at timestamptz NOT NULL,
    -- Refresh tokens rotate: a reused one revokes the grant (OAuth 2.1 §4.3.1).
    used_at timestamptz
);

CREATE INDEX mcp_tokens_grant ON mcp_tokens (grant_id);
CREATE INDEX mcp_tokens_expiry ON mcp_tokens (expires_at);

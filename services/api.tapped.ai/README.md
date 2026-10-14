
# Tapped API

the leading live music data analytics api for the music industry

check out our [webapp](https://app.tapped.ai) and [api docs](https://api.tapped.ai/docs)

## MCP server

`/mcp` is a remote [MCP](https://modelcontextprotocol.io) server (Streamable HTTP,
stateless, served by the official [`rmcp`](https://crates.io/crates/rmcp) SDK) that lets
performers use their Tapped account from
Claude or any MCP client. Connect with the URL `https://api.tapped.ai/mcp` (a custom
connector in Claude, or `claude mcp add --transport http tapped https://api.tapped.ai/mcp`).

Its seven tools are read-only (`src/domain/mcp/tools.rs`): `search` (performers,
venues and cities, like the web app), `get_profile`, `list_my_bookings`,
`get_booking`, `list_opportunities`, `search_opportunities` and `get_opportunity`.
Each calls the same handler the iOS app uses, as the signed-in user, so ownership and
privacy rules are identical.

Authorization is OAuth 2.1 (`src/domain/mcp/oauth.rs`, tables in
`migrations/20261022000000_mcp_oauth.sql`):

1. Discovery: `/.well-known/oauth-protected-resource/mcp` and
   `/.well-known/oauth-authorization-server`.
2. Dynamic client registration at `/oauth/register` (public clients only).
3. `/oauth/authorize` checks the client, redirect URI and PKCE (S256) and redirects to
   the consent page on app.tapped.ai, which calls
   `/oauth/authorization-requests/:id/approve` with the user's Firebase ID token (or `/deny`).
4. `/oauth/token` exchanges the single-use code (2 minutes) for a 1-hour access token
   and a 90-day refresh token. Refresh tokens rotate; replaying one revokes the
   connection. `/oauth/revoke` revokes a connection (RFC 7009).

Codes and tokens are stored only as SHA-256 hashes. A connection stops working when
the user's profile is deleted (checked at each refresh).

Configuration (production defaults shown): `MCP_ISSUER=https://api.tapped.ai` (the
OAuth issuer and token audience) and
`MCP_CONSENT_URL=https://app.tapped.ai/oauth/authorize`. For a local stack, point
them at the local API and web app.



## Identity/provider worker

`identity_worker` uses transaction-scoped per-UID locks to serialize Stream signup,
profile and deletion calls independently of Auth/API mutation locks. Configure a
Postgres pool with at least two connections (the worker currently uses five): a
provider-lock transaction stays open while current state is read through the pool.
Contended/failed jobs remain retryable; provider/database delivery is not exactly-once.

The default Stream endpoint is `https://chat.stream-io-api.com`. `STREAM_BASE_URL`
is an optional trusted deployment/test override; never derive it from request input.
Real retirement gates and rollout requirements are tracked in
[`platform/FIREBASE_FUNCTIONS_RETIREMENT.md`](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md).

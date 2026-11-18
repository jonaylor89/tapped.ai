
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

Push goes per device token: `device_tokens.provider='apns'` rows (current iOS builds)
are sent directly to APNs, `'fcm'` rows (builds before the APNs cutover) still go through
FCM until those builds age out. APNs uses token auth: put the App Store Connect `.p8`
key in `/opt/tapped/apns/` on the host and set `APNS_KEY_FILE=/run/secrets/apns/<file>.p8`,
`APNS_KEY_ID` and `APNS_TEAM_ID` (`APNS_TOPIC` defaults to `com.intheloopstudio`). The worker
runs as uid 10001, so the directory and key must be owned by it (`chown -R 10001:10001`, dir `0500`, key `0400`). Without
a key, APNs pushes stay queued in the outbox and retry. 410/`BadDeviceToken` prunes the token.

## Direct messages

In-house replacement for Stream Chat (`src/domain/direct_messages`). Postgres is the only store:

| Table | Role |
| --- | --- |
| `conversations` | One row per 1:1 pair (`direct_low < direct_high`, unique). `last_seq` is the newest message's sequence number; `frozen` means only the server may post. |
| `conversation_members` | `last_read_seq` (read cursor) and `sort_at` (inbox order, indexed per user). |
| `messages` | Client-generated UUID primary key (idempotent sends) and a gap-free `seq` per conversation. |

Unread for a member is `last_seq - last_read_seq`; sending advances the sender's cursor, so own
messages are never unread. Each send takes the conversation row lock, assigns `last_seq + 1`,
and in the same transaction enqueues APNs pushes (`external_effect_outbox`, delivered by the
identity worker) and the email mirror (venue email threads, or the DM email opt-in, in the SQLite
mail store), then `pg_notify`s. Clients use plain HTTP for writes:

```
GET  /app/v1/conversations?cursor=&limit=          inbox, newest first, plus unreadTotal
POST /app/v1/conversations/direct {userId}         get or create the 1:1 conversation
GET  /app/v1/conversations/{id}
GET  /app/v1/conversations/{id}/messages?before=|after=&limit=
POST /app/v1/conversations/{id}/messages {id, text}   201 new, 200 already stored (retry), 409 frozen
POST /app/v1/conversations/{id}/read {throughSeq?}
GET  /app/v1/conversations/events                  server-sent events (below)
```

**Realtime.** Every API process `LISTEN`s on `direct_messages`. For each committed event it reads
the member views once and pushes a JSON `data:` line to that member's SSE streams: `ready` (on
connect), `message`, `read` and `resync`. The stream sits outside the 90 s request timeout, sends
a keep-alive every 20 s, closes after about 25 minutes so clients reconnect with a fresh ID token,
and is closed on shutdown so deploys drain. A connection that falls 256 events behind is
dropped instead of blocking others. Nothing is replayed: clients resync on `ready`/`resync` and
fill `seq` gaps with `?after=`.

### Importing Stream history (`dm_import`)

`dm_import` copies every Stream `messaging` channel into these tables. It is idempotent and
resumable: conversations upsert on `legacy_stream_cid` (or the member pair), messages on
`legacy_stream_id`, read cursors only move forward, and each channel commits on its own. It skips
deleted, system and thread-only messages; channels whose members are not in `users`; and
community channels (two formal members that others post to, such as `tapped-promoter-chat`). The
JSON summary counts every skip. Imports send no pushes or realtime events. The API container
already has `DATABASE_URL` and the Stream keys:

```sh
tailscale ssh root@tapped-prod docker exec tapped-api-1 dm_import --dry-run
tailscale ssh root@tapped-prod docker exec tapped-api-1 dm_import
```

### Cutover

Old app builds talk to Stream directly, so the switch happens in two deploys:

1. Deploy this API (DM endpoints added; the Stream token, webhook and server-side Stream sends
   still serve old builds). Run `dm_import --dry-run`, check the skip counts, then `dm_import`.
2. Ship the iOS build that uses `TappedChatRepository` (it never talks to Stream).
3. Once that build is live, set `app_config.ios_minimum_app_version` to it so old builds stop
   writing to Stream, deploy the "retire Stream" change, and run `dm_import` again to pick up
   messages sent on Stream since step 1 (they are appended after existing history).
4. Compare `SELECT count(*) FROM messages WHERE legacy_stream_id IS NOT NULL` with the importer
   summary, then remove `STREAM_KEY`/`STREAM_SECRET` and delete the Stream app.

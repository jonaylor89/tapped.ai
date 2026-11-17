-- In-house direct messages (replaces Stream Chat). Postgres is the only store; clients read through the
-- API and receive realtime events via LISTEN/NOTIFY -> SSE (src/domain/direct_messages).
--
-- Ordering and unread counts come from a gap-free per-conversation sequence: every message takes
-- `conversations.last_seq + 1` under the conversation row lock, so a member's unread count is
-- `last_seq - last_read_seq` (the sender's read cursor advances with each send) and clients detect
-- missed realtime events as sequence gaps.
CREATE TABLE conversations (
    id              uuid PRIMARY KEY,
    -- 1:1 conversations are unique per unordered member pair. NULL for any future group conversation.
    direct_low      text,
    direct_high     text,
    created_by      text NOT NULL REFERENCES users(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    -- Server-controlled: only server deliveries may post (an unclaimed venue that has not replied yet).
    frozen          boolean NOT NULL DEFAULT false,
    last_seq        bigint NOT NULL DEFAULT 0 CHECK (last_seq >= 0),
    last_message_id uuid,
    last_message_at timestamptz,
    -- Provenance for conversations imported from Stream (`messaging:<id>`); re-imports upsert on it.
    legacy_stream_cid text UNIQUE,
    CHECK ((direct_low IS NULL) = (direct_high IS NULL)),
    CHECK (direct_low < direct_high),
    UNIQUE (direct_low, direct_high)
);

CREATE TABLE conversation_members (
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         text NOT NULL REFERENCES users(id),
    joined_at       timestamptz NOT NULL DEFAULT now(),
    last_read_seq   bigint NOT NULL DEFAULT 0 CHECK (last_read_seq >= 0),
    last_read_at    timestamptz,
    -- Inbox order (last activity), denormalized so the inbox is one index range scan per page.
    sort_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (conversation_id, user_id)
);
CREATE INDEX conversation_members_inbox ON conversation_members (user_id, sort_at DESC, conversation_id DESC);

CREATE TABLE messages (
    -- Client-generated, so a retried send is idempotent.
    id               uuid PRIMARY KEY,
    conversation_id  uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    seq              bigint NOT NULL CHECK (seq > 0),
    author_id        text NOT NULL REFERENCES users(id),
    body             text NOT NULL CHECK (length(body) <= 5000),
    -- [{"type":"image","url":"https://…"}]; imported from Stream, not yet sendable by clients.
    attachments      jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attachments) = 'array'),
    created_at       timestamptz NOT NULL DEFAULT now(),
    deleted_at       timestamptz,
    legacy_stream_id text UNIQUE,
    UNIQUE (conversation_id, seq)
);
CREATE INDEX messages_author_idx ON messages (author_id);

ALTER TABLE conversations
    ADD CONSTRAINT conversations_last_message_fk FOREIGN KEY (last_message_id) REFERENCES messages(id)
    DEFERRABLE INITIALLY DEFERRED;

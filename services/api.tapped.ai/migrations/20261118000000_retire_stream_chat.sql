-- Stream Chat is retired: direct messages live in Postgres and founder welcome messages are
-- posted in the profile-creating transaction. Close out queued Stream profile syncs (the worker
-- no longer knows the kind); delivered rows stay as history, so the kind stays allowed.
UPDATE external_effect_outbox
SET delivered_at = now(), lock_token = NULL, locked_until = NULL, last_error = 'retired: Stream Chat'
WHERE kind = 'stream_profile' AND delivered_at IS NULL;

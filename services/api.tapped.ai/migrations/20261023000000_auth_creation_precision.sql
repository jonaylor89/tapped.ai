-- Gen1 Auth hooks truncate creation times to seconds; Auth REST preserves milliseconds.
-- Normalize only the Rust identity ledger and lifecycle keys, without emitting/replaying jobs.
-- Firebase source accounts and original event payloads remain untouched. Firebase-generated
-- UIDs are never reused; ambiguous same-second administrative UID reuse fails closed.
UPDATE firebase_identities SET created_at_ms = created_at_ms / 1000 * 1000
WHERE created_at_ms % 1000 <> 0;

WITH normalized AS (
  SELECT id,
    'auth-' || CASE kind WHEN 'auth_signup' THEN 'signup' ELSE 'delete' END || ':' ||
    (payload->>'localId') || ':' ||
    (((payload->>'createdAt')::bigint / 1000 * 1000)::text) AS canonical_id,
    row_number() OVER (
      PARTITION BY kind, payload->>'localId', (payload->>'createdAt')::bigint / 1000
      ORDER BY delivered_at DESC NULLS LAST, id
    ) AS candidate
  FROM external_effect_outbox
  WHERE kind IN ('auth_signup','auth_delete')
    AND payload->>'createdAt' ~ '^[0-9]+$'
)
UPDATE external_effect_outbox e SET id = n.canonical_id
FROM normalized n
WHERE e.id = n.id AND n.candidate = 1 AND e.id <> n.canonical_id
  AND NOT EXISTS (SELECT 1 FROM external_effect_outbox existing WHERE existing.id = n.canonical_id);

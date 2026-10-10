-- Firestore usernames were normalized and deduplicated before this migration.
-- Keep the original display casing while enforcing case- and whitespace-insensitive uniqueness.
CREATE UNIQUE INDEX IF NOT EXISTS users_username_unique_ci_idx
    ON users (lower(btrim(username)))
    WHERE length(btrim(username)) > 0;

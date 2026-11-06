-- Run once on production, as the database owner, after review. Creates the scraper's schema and its role. Tables are
-- created by the scraper's own migrations, inside this schema only. Set the password separately, not in this file:
--   ALTER ROLE tapped_scraper PASSWORD '...';
BEGIN;

CREATE ROLE tapped_scraper LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT CONNECTION LIMIT 8;
-- Production allows 30 connections in total; a stuck laptop must not hold locks or sessions open.
ALTER ROLE tapped_scraper SET statement_timeout = '60s';
ALTER ROLE tapped_scraper SET lock_timeout = '30s';
ALTER ROLE tapped_scraper SET idle_in_transaction_session_timeout = '60s';

CREATE SCHEMA scraper AUTHORIZATION tapped_scraper;

-- Read-only, and only what the scraper needs: the columns that identify an event, not its payload.
GRANT USAGE ON SCHEMA public TO tapped_scraper;
GRANT SELECT (source, source_key, venue_id, title, start_time, event_url, music_classification)
  ON public.scraped_events TO tapped_scraper;
GRANT SELECT ON public.ingestion_profiles TO tapped_scraper;

COMMIT;

-- Removes everything production-bootstrap.sql and the scraper's migrations created. Application tables are untouched.
-- This deletes the scraper's sources, candidates and event history. Events it already published stay in scraped_events.
BEGIN;
DROP SCHEMA scraper CASCADE;
REVOKE ALL ON public.scraped_events, public.ingestion_profiles FROM tapped_scraper;
REVOKE USAGE ON SCHEMA public FROM tapped_scraper;
DROP ROLE tapped_scraper;
COMMIT;

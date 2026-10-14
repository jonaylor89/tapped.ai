-- Least-privilege producer role: no application counters, Auth writes or outbox permissions.
CREATE VIEW ingestion_profiles AS SELECT u.id,u.username,u.venue_website_url,
jsonb_build_object('id',u.id,'username',u.username,'artistName',u.artist_name,'bio',u.bio,
 'email','','unclaimed',u.unclaimed,'deleted',u.deleted,'occupations',u.occupations,'profilePicture',u.profile_picture,
 'location',CASE WHEN u.location IS NULL THEN NULL ELSE jsonb_build_object('lat',ST_Y(u.location::geometry),'lng',ST_X(u.location::geometry),'placeId',u.place_id) END,
 'performerInfo',CASE WHEN u.performer_enabled THEN jsonb_build_object('genres',u.performer_genres,'label',u.performer_label) END,
 'venueInfo',CASE WHEN u.venue_enabled THEN jsonb_build_object('genres',u.venue_genres,'websiteUrl',u.venue_website_url,'capacity',u.venue_capacity,'type',u.venue_type) END
) AS doc FROM users u WHERE NOT u.deleted AND NOT u.shadow_banned;
CREATE TABLE scrape_results (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), run_id text NOT NULL REFERENCES scrape_runs(id),
 source_key text NOT NULL, payload jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(run_id,source_key)
);
CREATE TABLE booking_imports (
 booking_id text PRIMARY KEY REFERENCES bookings(id),
 event_id text NOT NULL REFERENCES scraped_events(event_id)
);
CREATE INDEX booking_imports_event_idx ON booking_imports(event_id);
CREATE TABLE scraped_event_revisions (
 source text NOT NULL,source_key text NOT NULL,revision char(32) NOT NULL,payload jsonb NOT NULL,
 captured_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(source,source_key,revision)
);

CREATE FUNCTION ingest_unclaimed_artist(artist text, genres text[] DEFAULT '{}', venue text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE slug text; artist_id text;
BEGIN
 IF artist IS NULL OR length(btrim(artist)) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'invalid artist name'; END IF;
 slug := left(trim(both '-' FROM regexp_replace(lower(btrim(artist)),'[^a-z0-9]+','-','g')),50);
 IF slug='' THEN slug:='artist-'||md5(artist); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('ingestion-artist:'||slug,0));
 SELECT id INTO artist_id FROM public.users WHERE lower(btrim(username))=slug AND NOT deleted AND NOT venue_enabled;
 IF artist_id IS NOT NULL THEN RETURN artist_id; END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE lower(btrim(username))=slug) THEN slug:=slug||'-'||left(md5(artist),8); END IF;
 INSERT INTO public.users(id,username,artist_name,occupations,unclaimed,location,place_id,profile)
 SELECT gen_random_uuid()::text,slug,btrim(artist),ARRAY['performer'],true,v.location,v.place_id,
 jsonb_build_object('performerInfo',jsonb_build_object('genres',genres,'label','Independent'),'ingestionSource','scraper')
 FROM (SELECT 1) seed LEFT JOIN public.users v ON v.id=venue
 ON CONFLICT DO NOTHING RETURNING id INTO artist_id;
 IF artist_id IS NULL THEN SELECT id INTO artist_id FROM public.users WHERE lower(btrim(username))=slug AND NOT deleted AND NOT venue_enabled; END IF;
 IF artist_id IS NULL THEN RAISE EXCEPTION 'artist identity collision'; END IF;
 RETURN artist_id;
END $$;

CREATE FUNCTION ingest_scraped_event(producer text,key text,venue text,data jsonb) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
<<ingest_scraped_event>>
DECLARE event_id text; performer text; performer_id text; begins timestamptz; ends timestamptz; v public.users; ids text[] := '{}';
BEGIN
 IF producer IS NULL OR key IS NULL OR data IS NULL OR length(producer) NOT BETWEEN 1 AND 100 OR length(key) NOT BETWEEN 1 AND 4096 OR jsonb_typeof(data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid ingestion envelope'; END IF;
 SELECT * INTO v FROM public.users WHERE id=venue AND NOT deleted AND NOT shadow_banned AND venue_enabled;
 IF v.id IS NULL THEN RAISE EXCEPTION 'unknown venue'; END IF;
 begins:=(data->>'startTime')::timestamptz; ends:=(data->>'endTime')::timestamptz;
 IF begins IS NULL OR ends IS NULL OR NOT isfinite(begins) OR NOT isfinite(ends) OR begins>ends THEN RAISE EXCEPTION 'invalid event times'; END IF;
 IF jsonb_typeof(data->'isMusicEvent') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid music classification'; END IF;
 IF jsonb_typeof(data->'performers') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid performers'; END IF;
 IF jsonb_array_length(data->'performers')>100 OR EXISTS(SELECT 1 FROM jsonb_array_elements(data->'performers') p WHERE jsonb_typeof(p)<>'string') THEN RAISE EXCEPTION 'invalid performers'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('ingestion:'||producer||':'||key,0));
 IF EXISTS(SELECT 1 FROM public.scraped_events WHERE source=producer AND source_key=key AND venue_id<>venue) THEN RAISE EXCEPTION 'event venue is immutable'; END IF;
 event_id:='scraped-'||md5(producer||':'||key);
 INSERT INTO public.scraped_event_revisions(source,source_key,revision,payload) VALUES(producer,key,md5(data::text),data) ON CONFLICT DO NOTHING;
 INSERT INTO public.scraped_events(source,source_key,venue_id,event_id,payload)
 VALUES(producer,key,venue,event_id,data) ON CONFLICT(source,source_key) DO UPDATE SET payload=EXCLUDED.payload,updated_at=now();
 IF (data->>'isMusicEvent')::boolean IS NOT TRUE THEN
  UPDATE public.bookings b SET status='canceled' FROM public.booking_imports i WHERE b.id=i.booking_id AND i.event_id=ingest_scraped_event.event_id;
  RETURN event_id;
 END IF;
 FOR performer IN SELECT DISTINCT jsonb_array_elements_text(data->'performers') LOOP
  performer_id:=public.ingest_unclaimed_artist(performer,v.venue_genres,venue);
  ids:=array_append(ids,performer_id);
  INSERT INTO public.bookings(id,requester_id,requestee_id,status,name,note,rate,start_time,end_time,occurred_at,location,place_id,genres,flier_url,event_url,reference_event_id,profile)
  VALUES('scraped-booking-'||md5(event_id||':'||performer_id),venue,performer_id,'confirmed',coalesce(data->>'title',''),coalesce(data->>'description',''),0,begins,ends,now(),v.location,v.place_id,v.venue_genres,data->>'flierUrl',data->>'url',event_id,
  jsonb_build_object('ingestionSource',producer,'sourceKey',key,'crawlerInfo',jsonb_build_object('encodedLink',key),'scraperInfo',jsonb_build_object('runId',data->>'runId')))
  ON CONFLICT(id) DO UPDATE SET start_time=EXCLUDED.start_time,end_time=EXCLUDED.end_time,name=EXCLUDED.name,note=EXCLUDED.note,flier_url=EXCLUDED.flier_url,event_url=EXCLUDED.event_url,status='confirmed'
  WHERE EXISTS(SELECT 1 FROM public.booking_imports i WHERE i.booking_id=public.bookings.id AND i.event_id=ingest_scraped_event.event_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'booking identity collision'; END IF;
  INSERT INTO public.booking_imports(booking_id,event_id) VALUES('scraped-booking-'||md5(event_id||':'||performer_id),event_id) ON CONFLICT DO NOTHING;
 END LOOP;
 -- Only imported relationships for this exact event may be canceled by a re-scrape.
 UPDATE public.bookings b SET status='canceled' FROM public.booking_imports i WHERE b.id=i.booking_id AND i.event_id=ingest_scraped_event.event_id AND NOT(b.requestee_id=ANY(ids));
 RETURN event_id;
END $$;
REVOKE ALL ON FUNCTION ingest_unclaimed_artist(text,text[],text) FROM PUBLIC;
REVOKE ALL ON FUNCTION ingest_scraped_event(text,text,text,jsonb) FROM PUBLIC;
DO $$ BEGIN BEGIN CREATE ROLE tapped_ingestion NOLOGIN; EXCEPTION WHEN duplicate_object OR unique_violation THEN NULL; END; END $$;
GRANT USAGE ON SCHEMA public TO tapped_ingestion;
GRANT SELECT ON ingestion_profiles,scraped_events TO tapped_ingestion;
GRANT SELECT,INSERT,UPDATE ON scrape_runs,scrape_results TO tapped_ingestion;
GRANT EXECUTE ON FUNCTION ingest_unclaimed_artist(text,text[],text),ingest_scraped_event(text,text,text,jsonb) TO tapped_ingestion;
-- Provision a dedicated LOGIN member of tapped_ingestion outside source control. Never use the API's
-- owner credential in crawlers. No Firestore fallback or historical application notification replay.

-- Evidence capture is independent of application publication. No Auth/profile/booking/outbox effects.
-- Index fixed-size digests, not unbounded/URL-encoded source strings (btree tuples have a size cap).
CREATE FUNCTION scrape_key_hash(value text) RETURNS bytea LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$ SELECT sha256(convert_to(value,'UTF8')) $$;
CREATE TABLE scrape_objects (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 bucket text NOT NULL CHECK (bucket NOT IN ('tapped-media','tapped-media-archive') AND length(bucket) BETWEEN 3 AND 63),
 object_key text NOT NULL CHECK (object_key ~ '^(archive|evidence)/[a-f0-9]{2}/[a-f0-9]{64}\.gz$'),
 sha256 char(64) NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
 byte_size bigint NOT NULL CHECK (byte_size > 0),
 content_type text NOT NULL,
 content_encoding text NOT NULL CHECK (content_encoding='gzip'),
 CHECK(right(object_key,67)=sha256||'.gz'),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(bucket,object_key)
);

-- Scraper identities are provider identifiers, NOT application users or Firebase accounts.
ALTER TABLE scrape_runs DROP CONSTRAINT scrape_runs_scraper_id_fkey;
ALTER TABLE scrape_runs ADD COLUMN source text NOT NULL DEFAULT 'legacy-scrapers',
 ADD COLUMN parser_version text NOT NULL DEFAULT 'legacy',
 ADD COLUMN legacy_id text,
 ADD COLUMN status text NOT NULL DEFAULT 'running' CHECK(status IN ('running','completed','failed','interrupted')),
 ADD COLUMN evidence_id bigint REFERENCES scrape_objects(id),
 ADD COLUMN evidence_line integer CHECK(evidence_line > 0);
UPDATE scrape_runs SET status=CASE WHEN error IS NOT NULL THEN 'failed' WHEN ended_at IS NOT NULL THEN 'completed' ELSE 'interrupted' END;
CREATE INDEX scrape_runs_source_scraper_idx ON scrape_runs(source,scraper_id,started_at DESC);

CREATE TABLE scrape_targets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source text NOT NULL CHECK(length(source) BETWEEN 1 AND 100),
 source_key text NOT NULL CHECK(length(source_key) BETWEEN 1 AND 4096),
 source_key_hash bytea GENERATED ALWAYS AS (scrape_key_hash(source_key)) STORED,
 url text NOT NULL,
 venue_id text REFERENCES users(id),
 enabled boolean NOT NULL DEFAULT true,
 next_fetch_at timestamptz NOT NULL DEFAULT now(),
 lease_token uuid, lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 last_error text,
 UNIQUE(source,source_key_hash),
 CHECK((lease_token IS NULL)=(lease_until IS NULL))
);
CREATE INDEX scrape_targets_due_idx ON scrape_targets(next_fetch_at,id) WHERE enabled;

ALTER TABLE scraped_events ALTER COLUMN venue_id DROP NOT NULL;
ALTER TABLE scraped_events ADD COLUMN source_key_hash bytea GENERATED ALWAYS AS (scrape_key_hash(source_key)) STORED;
ALTER TABLE scraped_events DROP CONSTRAINT scraped_events_pkey;
ALTER TABLE scraped_events ADD PRIMARY KEY(source,source_key_hash);
ALTER TABLE scraped_events ADD COLUMN original_venue_id text,
 ADD COLUMN title text,
 ADD COLUMN description text,
 ADD COLUMN start_time timestamptz,
 ADD COLUMN end_time timestamptz,
 ADD COLUMN timezone text,
 ADD COLUMN date_precision text NOT NULL DEFAULT 'unknown' CHECK(date_precision IN ('instant','date','unknown')),
 ADD COLUMN music_classification text NOT NULL DEFAULT 'unknown' CHECK(music_classification IN ('music','non_music','unknown')),
 ADD COLUMN event_status text NOT NULL DEFAULT 'unknown' CHECK(event_status IN ('scheduled','canceled','postponed','unknown')),
 ADD COLUMN event_url text,
 ADD COLUMN flier_url text,
 ADD COLUMN first_seen_at timestamptz,
 ADD COLUMN last_seen_at timestamptz,
 ADD COLUMN last_changed_at timestamptz,
 ADD COLUMN current_observation_id uuid,
 ADD COLUMN publication_state text NOT NULL DEFAULT 'unpublished' CHECK(publication_state IN ('unpublished','published','held')),
 ADD CONSTRAINT scraped_events_time_order CHECK(start_time IS NULL OR end_time IS NULL OR start_time<=end_time),
 ADD CONSTRAINT scraped_events_finite_times CHECK((start_time IS NULL OR isfinite(start_time)) AND (end_time IS NULL OR isfinite(end_time)));
CREATE INDEX scraped_events_upcoming_idx ON scraped_events(start_time,event_id) WHERE music_classification='music';

ALTER TABLE scrape_results DROP CONSTRAINT scrape_results_run_id_source_key_key;
ALTER TABLE scrape_results ALTER COLUMN run_id DROP NOT NULL;
ALTER TABLE scrape_results ADD COLUMN source text NOT NULL DEFAULT 'legacy-scrapers',
 ADD COLUMN delivery_key text,
 ADD COLUMN legacy_run_id text,
 ADD COLUMN original_venue_id text,
 ADD COLUMN materialize boolean NOT NULL DEFAULT true,
 ADD COLUMN parser_version text NOT NULL DEFAULT 'legacy',
 ADD COLUMN observed_at timestamptz NOT NULL DEFAULT now() CHECK(isfinite(observed_at)),
 ADD COLUMN payload_hash char(64),
 ADD COLUMN evidence_id bigint REFERENCES scrape_objects(id),
 ADD COLUMN evidence_line integer CHECK(evidence_line > 0),
 ADD COLUMN event_id text REFERENCES scraped_events(event_id),
 ADD COLUMN processing_state text NOT NULL DEFAULT 'quarantined' CHECK(processing_state IN ('accepted','quarantined')),
 ADD COLUMN validation_errors jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(validation_errors)='array');
UPDATE scrape_results SET delivery_key=id::text,payload_hash=encode(sha256(convert_to(payload::text,'UTF8')),'hex');
ALTER TABLE scrape_results ALTER COLUMN delivery_key SET NOT NULL;
ALTER TABLE scrape_results ALTER COLUMN payload_hash SET NOT NULL;
ALTER TABLE scrape_results ADD CONSTRAINT scrape_results_delivery_unique UNIQUE(source,delivery_key),
 ADD CHECK(length(delivery_key) BETWEEN 1 AND 512),
 ADD CHECK(payload_hash ~ '^[a-f0-9]{64}$');
ALTER TABLE scraped_events ADD FOREIGN KEY(current_observation_id) REFERENCES scrape_results(id);
CREATE INDEX scrape_results_event_time_idx ON scrape_results(event_id,observed_at DESC);
CREATE INDEX scrape_results_run_idx ON scrape_results(run_id);
CREATE INDEX scrape_results_quarantine_idx ON scrape_results(created_at) WHERE processing_state='quarantined';

CREATE TABLE event_sources (
 source text NOT NULL, source_key text NOT NULL,
 source_key_hash bytea GENERATED ALWAYS AS (scrape_key_hash(source_key)) STORED,
 event_id text NOT NULL REFERENCES scraped_events(event_id),
 original_url text,
 normalization_version integer NOT NULL DEFAULT 1,
 PRIMARY KEY(source,source_key_hash)
);
INSERT INTO event_sources(source,source_key,event_id) SELECT source,source_key,event_id FROM scraped_events;
CREATE INDEX event_sources_event_idx ON event_sources(event_id);
CREATE TABLE event_performers (
 event_id text NOT NULL REFERENCES scraped_events(event_id),
 ordinal integer NOT NULL CHECK(ordinal>=0),
 raw_name text NOT NULL CHECK(length(raw_name) BETWEEN 1 AND 200),
 profile_id text REFERENCES users(id),
 resolution_method text,
 PRIMARY KEY(event_id,ordinal)
);
CREATE INDEX event_performers_profile_idx ON event_performers(profile_id) WHERE profile_id IS NOT NULL;
CREATE TABLE event_prices (
 event_id text NOT NULL REFERENCES scraped_events(event_id),
 ordinal integer NOT NULL CHECK(ordinal>=0),
 kind text NOT NULL CHECK(kind IN ('ticket','door','other')),
 amount_min numeric(14,4) CHECK(amount_min>=0),
 amount_max numeric(14,4) CHECK(amount_max>=amount_min),
 currency text CHECK(currency ~ '^[A-Z]{3}$'),
 description text,
 PRIMARY KEY(event_id,ordinal)
);

CREATE FUNCTION register_scrape_object(meta jsonb) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result public.scrape_objects;
BEGIN
 INSERT INTO public.scrape_objects(bucket,object_key,sha256,byte_size,content_type,content_encoding)
 VALUES(meta->>'bucket',meta->>'key',meta->>'sha256',(meta->>'bytes')::bigint,meta->>'contentType',meta->>'contentEncoding')
 ON CONFLICT(bucket,object_key) DO NOTHING;
 SELECT * INTO STRICT result FROM public.scrape_objects WHERE bucket=meta->>'bucket' AND object_key=meta->>'key';
 IF result.sha256<>meta->>'sha256' OR result.byte_size<>(meta->>'bytes')::bigint
 OR result.content_type<>meta->>'contentType' OR result.content_encoding<>meta->>'contentEncoding' THEN
  RAISE EXCEPTION 'evidence metadata collision';
 END IF;
 RETURN result.id;
END $$;

-- Accept bounded batches of sanitized extraction envelopes. Full originals live in private R2.
CREATE FUNCTION record_scrape_observations(batch jsonb)
RETURNS TABLE(observation_id uuid,event_id text,action text,issues jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE item jsonb; facts jsonb; errors jsonb; obs public.scrape_results; existing public.scraped_events; alias public.event_sources;
 venue text; event_key text; capture timestamptz; begins timestamptz; ends timestamptz; price jsonb; ord integer;
 evidence bigint; classification text; status text;
BEGIN
 IF jsonb_typeof(batch) IS DISTINCT FROM 'array' OR jsonb_array_length(batch)>500 THEN RAISE EXCEPTION 'invalid observation batch'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(batch) ORDER BY value->>'source',value->>'sourceKey',value->>'observedAt',value->>'deliveryKey' LOOP
  IF length(coalesce(item->>'source','')) NOT BETWEEN 1 AND 100
  OR (item->>'source') !~ '^[a-z][a-z0-9_-]{0,99}$'
  OR length(coalesce(item->>'sourceKey','')) NOT BETWEEN 1 AND 4096
  OR length(coalesce(item->>'deliveryKey','')) NOT BETWEEN 1 AND 512
  OR length(coalesce(item->>'parserVersion','')) NOT BETWEEN 1 AND 200
  OR jsonb_typeof(item->'facts') IS DISTINCT FROM 'object'
  OR jsonb_typeof(item->'errors') IS DISTINCT FROM 'array'
  OR (item ? 'materialize' AND jsonb_typeof(item->'materialize') IS DISTINCT FROM 'boolean')
  THEN RAISE EXCEPTION 'invalid observation envelope'; END IF;
  capture := (item->>'observedAt')::timestamptz;
  IF capture IS NULL OR NOT isfinite(capture) OR capture>now()+interval '5 minutes' THEN RAISE EXCEPTION 'invalid observation timestamp'; END IF;
  evidence := (item->>'evidenceId')::bigint;
  IF evidence IS NULL THEN RAISE EXCEPTION 'verified evidence is required'; END IF;
  PERFORM 1 FROM public.scrape_objects WHERE id=evidence;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown evidence'; END IF;
  SELECT jsonb_object_agg(key,value) INTO facts FROM jsonb_each(item->'facts')
   WHERE key=ANY(ARRAY['title','description','startTime','endTime','timezone','datePrecision','musicClassification','status','url','flierUrl','performers','prices']);
  facts:=coalesce(facts,'{}'::jsonb); errors := item->'errors'; begins := NULL; ends := NULL;
  classification := CASE WHEN facts->>'musicClassification' IN ('music','non_music','unknown') THEN facts->>'musicClassification' ELSE 'unknown' END;
  -- Defense in depth for callers bypassing the shared normalizer. Bad facts are retained, never served.
  BEGIN
   begins := (facts->>'startTime')::timestamptz; ends := (facts->>'endTime')::timestamptz;
   IF (begins IS NOT NULL AND NOT isfinite(begins)) OR (ends IS NOT NULL AND NOT isfinite(ends)) OR begins>ends THEN RAISE EXCEPTION 'bad times'; END IF;
   IF begins IS NULL AND classification<>'non_music' THEN errors := errors || '["missing_start_time"]'::jsonb; END IF;
   IF jsonb_typeof(facts->'performers') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'bad lineup'; END IF;
   IF jsonb_array_length(facts->'performers')>100 OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'performers') p WHERE jsonb_typeof(p)<>'string' OR length(p#>>'{}') NOT BETWEEN 1 AND 200) THEN RAISE EXCEPTION 'bad lineup'; END IF;
   IF jsonb_typeof(facts->'prices') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'bad prices'; END IF;
   IF jsonb_array_length(facts->'prices')>100 THEN RAISE EXCEPTION 'too many prices'; END IF;
   FOR price IN SELECT value FROM jsonb_array_elements(facts->'prices') LOOP
    -- Validate the actual storage precision here so rounding overflow is quarantined, not a
    -- late constraint error rolling back otherwise valid observations in the batch.
    PERFORM (price->>'amountMin')::numeric(14,4),(price->>'amountMax')::numeric(14,4);
    IF coalesce(price->>'kind','') NOT IN ('ticket','door','other')
    OR coalesce(price->>'currency','USD') !~ '^[A-Z]{3}$'
    OR (price->>'amountMin')::numeric<0 OR (price->>'amountMax')::numeric<(price->>'amountMin')::numeric
    OR abs((price->>'amountMin')::numeric)>=10000000000 OR abs((price->>'amountMax')::numeric)>=10000000000
    OR coalesce(price->>'amountMin','') IN ('NaN','Infinity','-Infinity') OR coalesce(price->>'amountMax','') IN ('NaN','Infinity','-Infinity')
    THEN RAISE EXCEPTION 'bad price'; END IF;
   END LOOP;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow OR invalid_text_representation OR raise_exception OR numeric_value_out_of_range THEN
   errors := errors || '["invalid_facts"]'::jsonb;
  END;
  status := CASE WHEN facts->>'status' IN ('scheduled','canceled','postponed','unknown') THEN facts->>'status' ELSE 'unknown' END;
  -- Serialize only this source item, not an artist name, venue, whole run, or producer.
  PERFORM pg_advisory_xact_lock(hashtextextended('observation:'||(item->>'source')||':'||(item->>'sourceKey'),0));
  SELECT * INTO obs FROM public.scrape_results r WHERE r.source=item->>'source' AND r.delivery_key=item->>'deliveryKey';
  IF FOUND THEN
   IF obs.source_key<>item->>'sourceKey' OR obs.payload<>facts OR obs.observed_at<>capture OR obs.parser_version<>item->>'parserVersion'
   OR obs.original_venue_id IS DISTINCT FROM item->>'venueId' OR obs.run_id IS DISTINCT FROM item->>'runId'
   OR obs.materialize IS DISTINCT FROM coalesce((item->>'materialize')::boolean,true)
   THEN RAISE EXCEPTION 'delivery identity collision'; END IF;
   observation_id:=obs.id; event_id:=obs.event_id; action:='duplicate'; issues:=obs.validation_errors; RETURN NEXT; CONTINUE;
  END IF;
  INSERT INTO public.scrape_results(source,source_key,delivery_key,run_id,legacy_run_id,original_venue_id,materialize,parser_version,observed_at,payload,payload_hash,evidence_id,evidence_line,validation_errors,processing_state)
  VALUES(item->>'source',item->>'sourceKey',item->>'deliveryKey',item->>'runId',item->>'legacyRunId',item->>'venueId',coalesce((item->>'materialize')::boolean,true),item->>'parserVersion',capture,facts,
   encode(sha256(convert_to(facts::text,'UTF8')),'hex'),evidence,(item->>'evidenceLine')::integer,errors,
   CASE WHEN jsonb_array_length(errors)=0 THEN 'accepted' ELSE 'quarantined' END) RETURNING * INTO obs;
  observation_id:=obs.id; event_id:=NULL; issues:=errors;
  IF jsonb_array_length(errors)>0 THEN action:='quarantined'; RETURN NEXT; CONTINUE; END IF;
  IF NOT obs.materialize THEN action:='archived'; RETURN NEXT; CONTINUE; END IF;
  SELECT * INTO existing FROM public.scraped_events e WHERE e.source=item->>'source' AND e.source_key_hash=public.scrape_key_hash(item->>'sourceKey');
  IF existing.event_id IS NOT NULL AND existing.source_key<>item->>'sourceKey' THEN RAISE EXCEPTION 'source identity collision'; END IF;
  IF existing.event_id IS NULL THEN
   SELECT * INTO alias FROM public.event_sources s WHERE s.source=item->>'source' AND s.source_key_hash=public.scrape_key_hash(item->>'sourceKey');
   IF alias.event_id IS NOT NULL THEN
    IF alias.source_key<>item->>'sourceKey' THEN RAISE EXCEPTION 'source identity collision'; END IF;
    -- An explicitly registered alias can attach evidence, but cannot silently replace another
    -- source's current facts. Choosing/merging authoritative sources is separate reconciliation.
    UPDATE public.scrape_results r SET event_id=alias.event_id WHERE r.id=obs.id;
    event_id:=alias.event_id; action:='archived'; RETURN NEXT; CONTINUE;
   END IF;
  END IF;
  event_key:=coalesce(existing.event_id,'scraped-'||md5((item->>'source')||':'||(item->>'sourceKey')));
  SELECT id INTO venue FROM public.users WHERE id=item->>'venueId';
  INSERT INTO public.scraped_events(source,source_key,venue_id,original_venue_id,event_id,payload,first_seen_at,last_seen_at)
  VALUES(item->>'source',item->>'sourceKey',venue,item->>'venueId',event_key,'{}',capture,capture)
  ON CONFLICT(source,source_key_hash) DO UPDATE SET first_seen_at=least(public.scraped_events.first_seen_at,capture),last_seen_at=greatest(public.scraped_events.last_seen_at,capture);
  INSERT INTO public.event_sources(source,source_key,event_id,original_url) VALUES(item->>'source',item->>'sourceKey',event_key,facts->>'url') ON CONFLICT DO NOTHING;
  UPDATE public.scrape_results r SET event_id=event_key WHERE r.id=obs.id;
  event_id:=event_key;
  -- Equal timestamps use delivery key ordering, making replay order deterministic.
  IF existing.current_observation_id IS NOT NULL AND EXISTS(
   SELECT 1 FROM public.scrape_results r WHERE r.id=existing.current_observation_id AND (r.observed_at,r.delivery_key)>=(capture,item->>'deliveryKey')
  ) THEN action:='historical'; RETURN NEXT; CONTINUE; END IF;
  -- A venue correction is held, not silently applied to an existing linked event.
  IF existing.venue_id IS NOT NULL AND existing.venue_id IS DISTINCT FROM venue THEN
   UPDATE public.scrape_results r SET processing_state='quarantined',validation_errors=r.validation_errors||'["venue_conflict"]'::jsonb WHERE r.id=obs.id;
   issues:=errors||'["venue_conflict"]'::jsonb; action:='quarantined'; RETURN NEXT; CONTINUE;
  END IF;
  UPDATE public.scraped_events e SET venue_id=venue,original_venue_id=item->>'venueId',title=facts->>'title',description=facts->>'description',
   start_time=begins,end_time=ends,timezone=facts->>'timezone',date_precision=CASE WHEN facts->>'datePrecision' IN ('instant','date','unknown') THEN facts->>'datePrecision' ELSE 'unknown' END,
   music_classification=classification,event_status=status,event_url=facts->>'url',flier_url=facts->>'flierUrl',
   current_observation_id=obs.id,last_changed_at=CASE WHEN e.payload IS DISTINCT FROM facts THEN capture ELSE e.last_changed_at END,
   payload=facts,updated_at=now() WHERE e.event_id=event_key;
  WITH previous AS (DELETE FROM public.event_performers p WHERE p.event_id=event_key RETURNING raw_name,profile_id,resolution_method),
  resolutions AS (SELECT DISTINCT ON(raw_name) * FROM previous ORDER BY raw_name,profile_id NULLS LAST)
  INSERT INTO public.event_performers(event_id,ordinal,raw_name,profile_id,resolution_method)
   SELECT event_key,(lineup.ordinality-1)::integer,lineup.value#>>'{}',p.profile_id,p.resolution_method
   FROM jsonb_array_elements(facts->'performers') WITH ORDINALITY AS lineup
   LEFT JOIN resolutions p ON p.raw_name=lineup.value#>>'{}';
  DELETE FROM public.event_prices p WHERE p.event_id=event_key;
  ord:=0;
  FOR price IN SELECT value FROM jsonb_array_elements(facts->'prices') LOOP
   INSERT INTO public.event_prices(event_id,ordinal,kind,amount_min,amount_max,currency,description)
   VALUES(event_key,ord,price->>'kind',(price->>'amountMin')::numeric,(price->>'amountMax')::numeric,price->>'currency',price->>'description');
   ord:=ord+1;
  END LOOP;
  action:=CASE WHEN existing.event_id IS NULL THEN 'inserted' ELSE 'updated' END; RETURN NEXT;
 END LOOP;
END $$;

-- Bounded work claiming. A stale worker cannot acknowledge a newer worker's lease.
CREATE FUNCTION claim_scrape_targets(max_items integer,lease_seconds integer DEFAULT 300)
RETURNS SETOF scrape_targets LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 WITH due AS (
 SELECT id FROM public.scrape_targets WHERE enabled AND next_fetch_at<=now() AND (lease_until IS NULL OR lease_until<=now())
 ORDER BY next_fetch_at,id LIMIT greatest(0,least(max_items,500)) FOR UPDATE SKIP LOCKED
 ) UPDATE public.scrape_targets t SET lease_token=gen_random_uuid(),lease_until=now()+make_interval(secs=>greatest(30,least(lease_seconds,3600))),attempts=attempts+1
 FROM due WHERE t.id=due.id RETURNING t.*
$$;
CREATE FUNCTION finish_scrape_target(target uuid,token uuid,next_fetch timestamptz,failure text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF next_fetch IS NULL OR NOT isfinite(next_fetch) OR next_fetch<=now() THEN RAISE EXCEPTION 'next fetch must be in the future'; END IF;
 UPDATE public.scrape_targets SET lease_token=NULL,lease_until=NULL,next_fetch_at=next_fetch,last_error=left(failure,1000)
 WHERE id=target AND lease_token=token AND lease_until>now();
 RETURN FOUND;
END $$;

REVOKE ALL ON FUNCTION register_scrape_object(jsonb),record_scrape_observations(jsonb),claim_scrape_targets(integer,integer),finish_scrape_target(uuid,uuid,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_scrape_object(jsonb),record_scrape_observations(jsonb),claim_scrape_targets(integer,integer),finish_scrape_target(uuid,uuid,timestamptz,text) TO tapped_ingestion;
GRANT SELECT ON scrape_targets,event_sources,event_performers,event_prices TO tapped_ingestion;
-- Explicitly retire the side-effecting path for owners as well as producers. Historical function
-- definitions remain in their original migration, never as a runnable publication mechanism.
CREATE OR REPLACE FUNCTION ingest_scraped_event(producer text,key text,venue text,data jsonb) RETURNS text
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'retired: use record_scrape_observations; publication requires separate reconciliation'; END $$;
CREATE OR REPLACE FUNCTION ingest_unclaimed_artist(artist text,genres text[] DEFAULT '{}',venue text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'retired: scraper names must remain unresolved until verified'; END $$;
REVOKE EXECUTE ON FUNCTION ingest_scraped_event(text,text,text,jsonb),ingest_unclaimed_artist(text,text[],text) FROM tapped_ingestion;
REVOKE INSERT,UPDATE ON scrape_results FROM tapped_ingestion;

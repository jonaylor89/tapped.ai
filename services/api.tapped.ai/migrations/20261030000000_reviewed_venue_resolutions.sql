-- Event/capture-scoped compatibility, NOT global profile aliases, identity merges or venue remaps.
CREATE FUNCTION scrape_venue_identity_hash(profile_id text) RETURNS text
LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
 SELECT encode(sha256(convert_to(jsonb_build_array(u.id,u.artist_name,u.username,u.venue_website_url,
 u.place_id,ST_AsEWKB(u.location::geometry)::text,u.venue_enabled,u.deleted,u.shadow_banned,u.unclaimed,
 EXISTS(SELECT 1 FROM public.profile_owners p WHERE p.profile_id=u.id))::text,'UTF8')),'hex')
 FROM public.users u WHERE u.id=profile_id
$$;
REVOKE ALL ON FUNCTION scrape_venue_identity_hash(text) FROM PUBLIC;

CREATE TABLE scrape_venue_resolutions (
 id text PRIMARY KEY CHECK(id ~ '^venue-resolution-[a-f0-9]{64}$'),
 observation_id uuid NOT NULL UNIQUE REFERENCES scrape_results(id),
 source text NOT NULL,source_key text NOT NULL,
 event_id text NOT NULL REFERENCES scraped_events(event_id),
 original_venue_id text NOT NULL REFERENCES users(id),
 preserved_venue_id text NOT NULL REFERENCES users(id),
 source_profile_hash char(64) NOT NULL,preserved_profile_hash char(64) NOT NULL,
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 100),
 evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
 created_at timestamptz NOT NULL DEFAULT now(),revoked_at timestamptz,
 CHECK(original_venue_id<>preserved_venue_id)
);
CREATE INDEX scrape_venue_resolutions_event_idx ON scrape_venue_resolutions(event_id);
ALTER TABLE scrape_results ADD COLUMN venue_resolution_id text REFERENCES scrape_venue_resolutions(id);

-- Owner/operator only. No EXECUTE or table write grant is given to producers.
CREATE FUNCTION approve_scrape_venue_resolution(producer text,delivery text,expected_event text,
 expected_preserved text,expected_source text,policy text,proof jsonb) RETURNS text
LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
DECLARE original public.scrape_results; anchor public.scraped_events; result public.scrape_venue_resolutions;
 resolution text; source_hash text; preserved_hash text;
BEGIN
 IF producer<>'event-crawler' OR length(coalesce(policy,'')) NOT BETWEEN 1 AND 100
 OR jsonb_typeof(proof) IS DISTINCT FROM 'object'
 OR coalesce(proof->>'kind','') NOT IN ('same_place_site_name_variant','same_branch_site_name_location')
 OR coalesce(proof->>'auditSha256','') !~ '^[a-f0-9]{64}$'
 OR coalesce(proof->>'sourceRootSha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'invalid venue review evidence'; END IF;
 SELECT * INTO STRICT original FROM public.scrape_results WHERE source=producer AND delivery_key=delivery;
 PERFORM pg_advisory_xact_lock(hashtextextended('observation:'||original.source||':'||original.source_key,0));
 SELECT * INTO STRICT anchor FROM public.scraped_events WHERE event_id=original.event_id FOR UPDATE;
 PERFORM 1 FROM public.users WHERE id IN (expected_source,expected_preserved) ORDER BY id FOR SHARE;
 source_hash:=public.scrape_venue_identity_hash(expected_source);
 preserved_hash:=public.scrape_venue_identity_hash(expected_preserved);
 IF original.normalization_version<>2 OR NOT original.materialize OR original.venue_resolution_id IS NOT NULL
 OR original.processing_state<>'quarantined' OR original.validation_errors<>'["venue_conflict"]'::jsonb
 OR original.original_venue_id IS DISTINCT FROM expected_source
 OR anchor.event_id<>expected_event OR anchor.venue_id IS DISTINCT FROM expected_preserved
 OR anchor.source<>original.source OR anchor.source_key<>original.source_key
 OR source_hash IS NULL OR preserved_hash IS NULL
 OR source_hash IS DISTINCT FROM proof->>'sourceProfileSha256'
 OR preserved_hash IS DISTINCT FROM proof->>'preservedProfileSha256'
 OR EXISTS(SELECT 1 FROM public.users u WHERE u.id IN (expected_source,expected_preserved)
  AND (NOT u.venue_enabled OR u.deleted OR u.shadow_banned OR NOT u.unclaimed))
 OR EXISTS(SELECT 1 FROM public.profile_owners p WHERE p.profile_id IN (expected_source,expected_preserved))
 THEN RAISE EXCEPTION 'venue review preconditions changed'; END IF;
 resolution:='venue-resolution-'||encode(sha256(convert_to(jsonb_build_array('venue-review-v1',original.source,
 original.delivery_key,anchor.event_id,anchor.venue_id,original.original_venue_id,policy)::text,'UTF8')),'hex');
 INSERT INTO public.scrape_venue_resolutions(id,observation_id,source,source_key,event_id,original_venue_id,
 preserved_venue_id,source_profile_hash,preserved_profile_hash,policy_version,evidence)
 VALUES(resolution,original.id,original.source,original.source_key,anchor.event_id,original.original_venue_id,
 anchor.venue_id,source_hash,preserved_hash,policy,proof) ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT result FROM public.scrape_venue_resolutions WHERE id=resolution;
 IF result.observation_id<>original.id OR result.evidence<>proof OR result.source_profile_hash<>source_hash
 OR result.preserved_profile_hash<>preserved_hash THEN RAISE EXCEPTION 'venue review identity collision'; END IF;
 RETURN resolution;
END $$;
REVOKE ALL ON FUNCTION approve_scrape_venue_resolution(text,text,text,text,text,text,jsonb) FROM PUBLIC;

CREATE OR REPLACE FUNCTION record_scrape_observations(batch jsonb)
RETURNS TABLE(observation_id uuid,event_id text,action text,issues jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE item jsonb; facts jsonb; errors jsonb; obs public.scrape_results; existing public.scraped_events; alias public.event_sources;
 venue text; event_key text; capture timestamptz; begins timestamptz; ends timestamptz; price jsonb; ord integer;
 evidence bigint; classification text; status text;
 normalization smallint; input_unit text; notes jsonb; canonical_prices jsonb; projection jsonb;
 resolution_key text; reviewed public.scrape_venue_resolutions; reviewed_source public.scrape_results;
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
  normalization:=coalesce((item->>'normalizationVersion')::smallint,1);
  input_unit:=item->>'inputPriceUnit'; notes:=coalesce(item->'normalizationNotes','[]'::jsonb);
  IF normalization NOT IN (1,2) OR jsonb_typeof(notes)<>'array' OR jsonb_array_length(notes)>50
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(notes) n WHERE jsonb_typeof(n)<>'string')
   OR (normalization=1 AND input_unit IS NOT NULL)
   OR (normalization=2 AND (input_unit IS NULL OR input_unit NOT IN ('usd_major','usd_cent') OR item->'facts'->>'priceUnit' IS DISTINCT FROM 'usd_cent'))
   OR (normalization=1 AND item->'facts' ? 'priceUnit')
  THEN RAISE EXCEPTION 'invalid normalization envelope'; END IF;
  resolution_key:=item->>'venueResolutionId';
  IF resolution_key IS NOT NULL AND (normalization<>2 OR resolution_key !~ '^venue-resolution-[a-f0-9]{64}$') THEN
   RAISE EXCEPTION 'invalid venue resolution envelope'; END IF;
  capture := (item->>'observedAt')::timestamptz;
  IF capture IS NULL OR NOT isfinite(capture) OR capture>now()+interval '5 minutes' THEN RAISE EXCEPTION 'invalid observation timestamp'; END IF;
  evidence := (item->>'evidenceId')::bigint;
  IF evidence IS NULL THEN RAISE EXCEPTION 'verified evidence is required'; END IF;
  PERFORM 1 FROM public.scrape_objects WHERE id=evidence;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown evidence'; END IF;
  SELECT jsonb_object_agg(key,value) INTO facts FROM jsonb_each(item->'facts')
   WHERE key=ANY(ARRAY['title','description','startTime','endTime','timezone','datePrecision','musicClassification','status','url','flierUrl','performers','prices','priceUnit']);
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
   canonical_prices:='[]'::jsonb;
   FOR price IN SELECT value FROM jsonb_array_elements(facts->'prices') LOOP
    canonical_prices:=canonical_prices||jsonb_build_array(public.scrape_price_in_cents(price,normalization));
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
   OR obs.normalization_version<>normalization OR obs.input_price_unit IS DISTINCT FROM input_unit OR obs.normalization_notes<>notes OR obs.venue_resolution_id IS DISTINCT FROM resolution_key
   THEN RAISE EXCEPTION 'delivery identity collision'; END IF;
   observation_id:=obs.id; event_id:=obs.event_id; action:='duplicate'; issues:=obs.validation_errors; RETURN NEXT; CONTINUE;
  END IF;
  -- Only operator-reviewed exact captured facts may use an event-scoped compatibility decision.
  IF resolution_key IS NOT NULL THEN
   SELECT * INTO reviewed FROM public.scrape_venue_resolutions WHERE id=resolution_key AND revoked_at IS NULL;
   IF NOT FOUND THEN RAISE EXCEPTION 'unapproved venue resolution'; END IF;
   SELECT * INTO STRICT reviewed_source FROM public.scrape_results WHERE id=reviewed.observation_id;
   PERFORM 1 FROM public.users WHERE id IN (reviewed.original_venue_id,reviewed.preserved_venue_id) ORDER BY id FOR SHARE;
   IF reviewed.source<>item->>'source' OR reviewed.source_key<>item->>'sourceKey'
    OR reviewed.original_venue_id IS DISTINCT FROM item->>'venueId'
    OR reviewed_source.observed_at<>capture OR reviewed_source.payload<>facts
    OR reviewed_source.run_id IS DISTINCT FROM item->>'runId'
    OR reviewed_source.legacy_run_id IS DISTINCT FROM item->>'legacyRunId'
    OR reviewed_source.normalization_version<>normalization
    OR reviewed_source.input_price_unit IS DISTINCT FROM input_unit
    OR reviewed_source.evidence_id<>evidence
    OR reviewed_source.evidence_line IS DISTINCT FROM (item->>'evidenceLine')::integer
    OR reviewed_source.parser_version||':venue-review-v1'<>item->>'parserVersion'
    OR NOT coalesce((item->>'materialize')::boolean,true) OR jsonb_array_length(errors)<>0
    OR reviewed.source_profile_hash IS DISTINCT FROM public.scrape_venue_identity_hash(reviewed.original_venue_id)
    OR reviewed.preserved_profile_hash IS DISTINCT FROM public.scrape_venue_identity_hash(reviewed.preserved_venue_id)
    OR NOT EXISTS(SELECT 1 FROM public.scraped_events e WHERE e.event_id=reviewed.event_id
     AND e.source=reviewed.source AND e.source_key=reviewed.source_key AND e.venue_id=reviewed.preserved_venue_id)
   THEN RAISE EXCEPTION 'venue resolution scope or evidence changed'; END IF;
  END IF;
  INSERT INTO public.scrape_results(source,source_key,delivery_key,run_id,legacy_run_id,original_venue_id,materialize,parser_version,observed_at,payload,payload_hash,evidence_id,evidence_line,validation_errors,processing_state,normalization_version,input_price_unit,normalization_notes,venue_resolution_id)
  VALUES(item->>'source',item->>'sourceKey',item->>'deliveryKey',item->>'runId',item->>'legacyRunId',item->>'venueId',coalesce((item->>'materialize')::boolean,true),item->>'parserVersion',capture,facts,
   encode(sha256(convert_to(facts::text,'UTF8')),'hex'),evidence,(item->>'evidenceLine')::integer,errors,
   CASE WHEN jsonb_array_length(errors)=0 THEN 'accepted' ELSE 'quarantined' END,normalization,input_unit,notes,resolution_key) RETURNING * INTO obs;
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
  IF resolution_key IS NOT NULL THEN venue:=reviewed.preserved_venue_id;
  ELSE SELECT id INTO venue FROM public.users WHERE id=item->>'venueId'; END IF;
  INSERT INTO public.scraped_events(source,source_key,venue_id,original_venue_id,event_id,payload,first_seen_at,last_seen_at)
  VALUES(item->>'source',item->>'sourceKey',venue,item->>'venueId',event_key,'{}',capture,capture)
  ON CONFLICT(source,source_key_hash) DO UPDATE SET first_seen_at=least(public.scraped_events.first_seen_at,capture),last_seen_at=greatest(public.scraped_events.last_seen_at,capture);
  INSERT INTO public.event_sources(source,source_key,event_id,original_url) VALUES(item->>'source',item->>'sourceKey',event_key,facts->>'url') ON CONFLICT DO NOTHING;
  UPDATE public.scrape_results r SET event_id=event_key WHERE r.id=obs.id;
  event_id:=event_key;
  -- Newer captures win first; at the same capture, v2 supersedes v1 regardless of delivery hash.
  IF existing.current_observation_id IS NOT NULL AND EXISTS(
   SELECT 1 FROM public.scrape_results r WHERE r.id=existing.current_observation_id AND (r.observed_at,r.normalization_version,r.venue_resolution_id IS NOT NULL,r.delivery_key)>=(capture,normalization,resolution_key IS NOT NULL,item->>'deliveryKey')
  ) THEN action:='historical'; RETURN NEXT; CONTINUE; END IF;
  -- A venue correction is held, not silently applied to an existing linked event.
  IF existing.venue_id IS NOT NULL AND existing.venue_id IS DISTINCT FROM venue THEN
   UPDATE public.scrape_results r SET processing_state='quarantined',validation_errors=r.validation_errors||'["venue_conflict"]'::jsonb WHERE r.id=obs.id;
   issues:=errors||'["venue_conflict"]'::jsonb; action:='quarantined'; RETURN NEXT; CONTINUE;
  END IF;
  projection:=facts||jsonb_build_object('priceUnit','usd_cent','prices',canonical_prices);
  UPDATE public.scraped_events e SET venue_id=venue,original_venue_id=item->>'venueId',title=facts->>'title',description=facts->>'description',
   start_time=begins,end_time=ends,timezone=facts->>'timezone',date_precision=CASE WHEN facts->>'datePrecision' IN ('instant','date','unknown') THEN facts->>'datePrecision' ELSE 'unknown' END,
   music_classification=classification,event_status=status,event_url=facts->>'url',flier_url=facts->>'flierUrl',
   current_observation_id=obs.id,last_changed_at=CASE WHEN e.payload IS DISTINCT FROM projection THEN capture ELSE e.last_changed_at END,
   payload=projection,updated_at=now() WHERE e.event_id=event_key;
  WITH previous AS (DELETE FROM public.event_performers p WHERE p.event_id=event_key RETURNING raw_name,profile_id,resolution_method),
  resolutions AS (SELECT DISTINCT ON(raw_name) * FROM previous ORDER BY raw_name,profile_id NULLS LAST)
  INSERT INTO public.event_performers(event_id,ordinal,raw_name,profile_id,resolution_method)
   SELECT event_key,(lineup.ordinality-1)::integer,lineup.value#>>'{}',p.profile_id,p.resolution_method
   FROM jsonb_array_elements(facts->'performers') WITH ORDINALITY AS lineup
   LEFT JOIN resolutions p ON p.raw_name=lineup.value#>>'{}';
  DELETE FROM public.event_prices p WHERE p.event_id=event_key;
  ord:=0;
  FOR price IN SELECT value FROM jsonb_array_elements(canonical_prices) LOOP
   INSERT INTO public.event_prices(event_id,ordinal,kind,amount_min_cents,amount_max_cents,currency,description)
   VALUES(event_key,ord,price->>'kind',(price->>'amountMinCents')::bigint,(price->>'amountMaxCents')::bigint,'USD',price->>'description');
   ord:=ord+1;
  END LOOP;
  action:=CASE WHEN existing.event_id IS NULL THEN 'inserted' ELSE 'updated' END; RETURN NEXT;
 END LOOP;
END $$;

-- Approved historical USD assumption. Canonical prices are integer cents; v1 evidence/observations stay immutable.
-- Fail instead of rounding or relabeling any pre-existing value that needs a separate decision.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM event_prices WHERE currency IS NOT NULL AND currency<>'USD') THEN
  RAISE EXCEPTION 'Explicit non-USD prices require review before cents migration';
 END IF;
 IF EXISTS(SELECT 1 FROM event_prices WHERE amount_min*100<>trunc(amount_min*100) OR amount_max*100<>trunc(amount_max*100)) THEN
  RAISE EXCEPTION 'Fractional cents require review before cents migration';
 END IF;
END $$;
ALTER TABLE event_prices RENAME COLUMN amount_min TO amount_min_cents;
ALTER TABLE event_prices RENAME COLUMN amount_max TO amount_max_cents;
ALTER TABLE event_prices ALTER COLUMN amount_min_cents TYPE bigint USING (amount_min_cents*100)::bigint,
 ALTER COLUMN amount_max_cents TYPE bigint USING (amount_max_cents*100)::bigint;
UPDATE event_prices SET currency='USD' WHERE currency IS NULL;
ALTER TABLE event_prices ALTER COLUMN currency SET DEFAULT 'USD', ALTER COLUMN currency SET NOT NULL,
 ADD CHECK(currency='USD'),
 ADD CHECK(amount_min_cents>=0 AND amount_min_cents<1000000000000),
 ADD CHECK(amount_max_cents>=0 AND amount_max_cents<1000000000000);

ALTER TABLE scrape_results ADD COLUMN normalization_version smallint NOT NULL DEFAULT 1 CHECK(normalization_version IN (1,2)),
 ADD COLUMN input_price_unit text,
 ADD COLUMN normalization_notes jsonb NOT NULL DEFAULT '[]' CHECK(jsonb_typeof(normalization_notes)='array'),
 ADD CHECK((normalization_version=1 AND input_price_unit IS NULL) OR
 (normalization_version=2 AND input_price_unit IS NOT NULL AND input_price_unit IN ('usd_major','usd_cent')));
CREATE INDEX scrape_results_source_version_idx ON scrape_results(source,scrape_key_hash(source_key),observed_at DESC,normalization_version DESC);

-- Only the current projection is re-expressed. Original v1 observation JSON remains dollar-major.
UPDATE scraped_events e SET payload=e.payload||jsonb_build_object('priceUnit','usd_cent','prices',
 coalesce((SELECT jsonb_agg(jsonb_build_object('kind',p.kind,'amountMinCents',p.amount_min_cents,
 'amountMaxCents',p.amount_max_cents,'currency',p.currency,'description',p.description) ORDER BY p.ordinal)
 FROM event_prices p WHERE p.event_id=e.event_id),'[]'::jsonb));

CREATE FUNCTION scrape_price_in_cents(price jsonb,normalization smallint) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
DECLARE min_value numeric; max_value numeric; min_key text; max_key text;
BEGIN
 IF normalization NOT IN (1,2) OR jsonb_typeof(price)<>'object'
 OR coalesce(price->>'kind','') NOT IN ('ticket','door','other')
 OR coalesce(price->>'currency','USD')<>'USD' THEN RAISE EXCEPTION 'invalid price'; END IF;
 IF normalization=2 THEN
  IF price ? 'amountMin' OR price ? 'amountMax' THEN RAISE EXCEPTION 'ambiguous price unit'; END IF;
  min_key:='amountMinCents'; max_key:='amountMaxCents';
 ELSE
  IF price ? 'amountMinCents' OR price ? 'amountMaxCents' THEN RAISE EXCEPTION 'ambiguous price unit'; END IF;
  min_key:='amountMin'; max_key:='amountMax';
 END IF;
 IF (price ? min_key AND jsonb_typeof(price->min_key) NOT IN ('number','null'))
 OR (price ? max_key AND jsonb_typeof(price->max_key) NOT IN ('number','null'))
 THEN RAISE EXCEPTION 'invalid price type'; END IF;
 min_value:=(price->>min_key)::numeric; max_value:=(price->>max_key)::numeric;
 IF normalization=1 THEN min_value:=min_value*100; max_value:=max_value*100; END IF;
 IF min_value<0 OR max_value<0 OR max_value<min_value OR min_value>=1000000000000 OR max_value>=1000000000000
 OR min_value<>trunc(min_value) OR max_value<>trunc(max_value) THEN RAISE EXCEPTION 'invalid cents'; END IF;
 RETURN jsonb_build_object('kind',price->>'kind','amountMinCents',min_value::bigint,'amountMaxCents',max_value::bigint,
 'currency','USD','description',price->>'description');
END $$;
REVOKE ALL ON FUNCTION scrape_price_in_cents(jsonb,smallint) FROM PUBLIC;

CREATE OR REPLACE FUNCTION record_scrape_observations(batch jsonb)
RETURNS TABLE(observation_id uuid,event_id text,action text,issues jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE item jsonb; facts jsonb; errors jsonb; obs public.scrape_results; existing public.scraped_events; alias public.event_sources;
 venue text; event_key text; capture timestamptz; begins timestamptz; ends timestamptz; price jsonb; ord integer;
 evidence bigint; classification text; status text;
 normalization smallint; input_unit text; notes jsonb; canonical_prices jsonb; projection jsonb;
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
   OR obs.normalization_version<>normalization OR obs.input_price_unit IS DISTINCT FROM input_unit OR obs.normalization_notes<>notes
   THEN RAISE EXCEPTION 'delivery identity collision'; END IF;
   observation_id:=obs.id; event_id:=obs.event_id; action:='duplicate'; issues:=obs.validation_errors; RETURN NEXT; CONTINUE;
  END IF;
  INSERT INTO public.scrape_results(source,source_key,delivery_key,run_id,legacy_run_id,original_venue_id,materialize,parser_version,observed_at,payload,payload_hash,evidence_id,evidence_line,validation_errors,processing_state,normalization_version,input_price_unit,normalization_notes)
  VALUES(item->>'source',item->>'sourceKey',item->>'deliveryKey',item->>'runId',item->>'legacyRunId',item->>'venueId',coalesce((item->>'materialize')::boolean,true),item->>'parserVersion',capture,facts,
   encode(sha256(convert_to(facts::text,'UTF8')),'hex'),evidence,(item->>'evidenceLine')::integer,errors,
   CASE WHEN jsonb_array_length(errors)=0 THEN 'accepted' ELSE 'quarantined' END,normalization,input_unit,notes) RETURNING * INTO obs;
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
  -- Newer captures win first; at the same capture, v2 supersedes v1 regardless of delivery hash.
  IF existing.current_observation_id IS NOT NULL AND EXISTS(
   SELECT 1 FROM public.scrape_results r WHERE r.id=existing.current_observation_id AND (r.observed_at,r.normalization_version,r.delivery_key)>=(capture,normalization,item->>'deliveryKey')
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

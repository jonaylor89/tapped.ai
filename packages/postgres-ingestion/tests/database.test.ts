import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { Pool } from "pg";
import {
  type EvidenceRef,
  normalizeObservation,
  type ObservationInput,
  recordObservations,
  registerEvidence,
} from "../src/index";

const url = process.env.INGESTION_TEST_DATABASE_URL;
// Creates and drops ONLY a fresh random local test database, never runs on an operator's target DB.
test("relational observation ingestion, populated migration, and producer permissions", { skip: !url }, async (t) => {
  const base = new URL(url as string);
  if (!["127.0.0.1", "localhost"].includes(base.hostname))
    throw new Error("Integration tests require a local database");
  const admin = new Pool({ connectionString: base.href, max: 1 });
  const name = `ingestion_${randomUUID().replaceAll("-", "")}`;
  await admin.query(`CREATE DATABASE ${name}`);
  base.pathname = `/${name}`;
  const pool = new Pool({ connectionString: base.href, max: 1 });
  try {
    const folder = resolve(__dirname, "../../../services/api.tapped.ai/migrations");
    const files = (await readdir(folder)).filter((f) => f.endsWith(".sql")).sort();
    for (const file of files.filter((f) => f < "20261028000000"))
      await pool.query(await readFile(resolve(folder, file), "utf8"));
    await pool.query(`INSERT INTO users(id,username,profile) VALUES('venue','venue','{"venueInfo":{}}'),('artist','artist','{}');
      INSERT INTO bookings(id,requester_id,requestee_id,status) VALUES('original-booking','venue','artist','confirmed');
      INSERT INTO scraped_events(source,source_key,venue_id,event_id,payload) VALUES('event-crawler','existing','venue','preserved-event-id','{"legacyBaseline":true}');
      INSERT INTO scrape_runs(id,scraper_id) VALUES('old-run','venue');
      INSERT INTO scrape_results(run_id,source_key,payload) VALUES('old-run','old-result','{}');`);
    for (const file of files.filter((f) => f >= "20261028000000"))
      await pool.query(await readFile(resolve(folder, file), "utf8"));
    const evidence: EvidenceRef = {
      bucket: "tapped-scrape-private-test",
      key: `archive/aa/${"a".repeat(64)}.gz`,
      sha256: "a".repeat(64),
      bytes: 100,
      contentType: "application/x-ndjson",
      contentEncoding: "gzip",
    };
    const input: ObservationInput = {
      source: "event-crawler",
      sourceKey: "existing",
      deliveryKey: "first",
      observedAt: "2020-01-02T00:00:00Z",
      parserVersion: "test-v1",
      venueId: "venue",
      data: {
        title: "Original",
        startTime: "2030-01-01T20:00:00Z",
        performers: ["Artist name"],
        isMusicEvent: true,
        ticketPrice: 0,
      },
    };
    await t.test("manifest roots remain registered without observation or business side effects", async () => {
      const root = { ...evidence, key: `archive/bb/${"b".repeat(64)}.gz`, sha256: "b".repeat(64) };
      const id = await registerEvidence(pool, root);
      assert.equal(await registerEvidence(pool, root), id);
      assert.equal((await pool.query("SELECT count(*) FROM scrape_objects WHERE id=$1", [id])).rows[0].count, "1");
      assert.equal((await pool.query("SELECT count(*) FROM scrape_results")).rows[0].count, "1");
      assert.equal((await pool.query("SELECT count(*) FROM bookings")).rows[0].count, "1");
      assert.equal((await pool.query("SELECT count(*) FROM users")).rows[0].count, "2");
    });
    await t.test("preserves populated historical rows and event IDs without business effects", async () => {
      const [result] = await recordObservations(pool, [input], evidence);
      assert.equal(result.action, "updated");
      assert.equal(result.event_id, "preserved-event-id");
      assert.equal((await pool.query("SELECT count(*) FROM users")).rows[0].count, "2");
      assert.equal((await pool.query("SELECT count(*) FROM bookings")).rows[0].count, "1");
      assert.equal(
        (await pool.query("SELECT status FROM bookings WHERE id='original-booking'")).rows[0].status,
        "confirmed",
      );
      assert.equal((await pool.query("SELECT count(*) FROM external_effect_outbox")).rows[0].count, "0");
      assert.equal(
        (await pool.query("SELECT raw_name,profile_id FROM event_performers")).rows[0].raw_name,
        "Artist name",
      );
      assert.equal((await pool.query("SELECT amount_min_cents,currency FROM event_prices")).rows[0].currency, "USD");
      await pool.query(
        "UPDATE event_performers SET profile_id='artist',resolution_method='verified' WHERE raw_name='Artist name'",
      );
      const [duplicate] = await recordObservations(pool, [input], evidence);
      assert.equal(duplicate.action, "duplicate");
      assert.equal(duplicate.observation_id, result.observation_id);
      await assert.rejects(
        recordObservations(pool, [{ ...input, data: { ...input.data, title: "collision" } }], evidence),
        /identity collision/,
      );
    });
    await t.test("out-of-order observations cannot overwrite current facts", async () => {
      const older = {
        ...input,
        deliveryKey: "older",
        observedAt: "2020-01-01T00:00:00Z",
        data: { ...input.data, title: "Older" },
      };
      assert.equal((await recordObservations(pool, [older], evidence))[0].action, "historical");
      assert.equal(
        (await pool.query("SELECT title FROM scraped_events WHERE event_id='preserved-event-id'")).rows[0].title,
        "Original",
      );
      const later = {
        ...input,
        deliveryKey: "later",
        observedAt: "2020-01-03T00:00:00Z",
        data: { ...input.data, isMusicEvent: false },
      };
      await recordObservations(pool, [later], evidence);
      assert.equal(
        (await pool.query("SELECT profile_id FROM event_performers WHERE event_id='preserved-event-id'")).rows[0]
          .profile_id,
        "artist",
      );
      assert.equal(
        (await pool.query("SELECT music_classification FROM scraped_events WHERE event_id='preserved-event-id'"))
          .rows[0].music_classification,
        "non_music",
      );
      assert.equal(
        (await pool.query("SELECT status FROM bookings WHERE id='original-booking'")).rows[0].status,
        "confirmed",
      );
    });
    await t.test(
      "explicit aliases attach evidence without duplicating events or choosing a new authority",
      async () => {
        await pool.query(
          "INSERT INTO event_sources(source,source_key,event_id) VALUES('other-source','redirect','preserved-event-id')",
        );
        const [result] = await recordObservations(
          pool,
          [{ ...input, source: "other-source", sourceKey: "redirect", deliveryKey: "alias" }],
          evidence,
        );
        assert.equal(result.action, "archived");
        assert.equal(result.event_id, "preserved-event-id");
        assert.equal(
          (await pool.query("SELECT count(*) FROM scraped_events WHERE source_key='redirect'")).rows[0].count,
          "0",
        );
      },
    );
    await t.test("observation statements roll back a whole batch on invalid envelope identity", async () => {
      const evidenceId = await registerEvidence(pool, evidence);
      const good = { ...normalizeObservation({ ...input, sourceKey: "atomic", deliveryKey: "atomic" }), evidenceId };
      const bad = { ...good, source: "zzz", sourceKey: "" };
      await assert.rejects(
        pool.query("SELECT * FROM record_scrape_observations($1::jsonb)", [JSON.stringify([good, bad])]),
        /invalid observation envelope/,
      );
      assert.equal(
        (await pool.query("SELECT count(*) FROM scrape_results WHERE delivery_key='atomic'")).rows[0].count,
        "0",
      );
    });
    await t.test("long source keys use fixed-size indexes and source namespaces remain independent", async () => {
      const key = randomBytes(3072).toString("base64");
      const [first] = await recordObservations(pool, [{ ...input, sourceKey: key, deliveryKey: "long-key" }], evidence);
      const [other] = await recordObservations(
        pool,
        [{ ...input, source: "other-source", sourceKey: key, deliveryKey: "long-key" }],
        evidence,
      );
      assert.notEqual(first.event_id, other.event_id);
      const row = (
        await pool.query(
          "SELECT source_key,octet_length(source_key_hash) AS bytes FROM scraped_events WHERE event_id=$1",
          [first.event_id],
        )
      ).rows[0];
      assert.equal(row.source_key, key);
      assert.equal(row.bytes, 32);
    });
    await t.test("source microseconds survive normalization and stale captures cannot win a rounded tie", async () => {
      const newer = {
        ...input,
        sourceKey: "micro",
        deliveryKey: "a",
        observedAt: "2020-01-01T00:00:00.000002Z",
        data: { ...input.data, title: "Newer" },
      };
      const older = {
        ...newer,
        deliveryKey: "z",
        observedAt: "2020-01-01T00:00:00.000001Z",
        data: { ...input.data, title: "Older" },
      };
      const [current] = await recordObservations(pool, [newer], evidence);
      assert.equal((await recordObservations(pool, [older], evidence))[0].action, "historical");
      assert.equal(
        (await pool.query("SELECT title FROM scraped_events WHERE event_id=$1", [current.event_id])).rows[0].title,
        "Newer",
      );
    });
    await t.test(
      "negative page classifications persist without event dates and malformed text is quarantined",
      async () => {
        const [negative] = await recordObservations(
          pool,
          [{ ...input, sourceKey: "negative", deliveryKey: "negative", data: { isMusicEvent: false } }],
          evidence,
        );
        assert.equal(negative.action, "inserted");
        const row = (
          await pool.query("SELECT start_time,music_classification FROM scraped_events WHERE event_id=$1", [
            negative.event_id,
          ])
        ).rows[0];
        assert.equal(row.start_time, null);
        assert.equal(row.music_classification, "non_music");
        const [badText] = await recordObservations(
          pool,
          [{ ...input, sourceKey: "nul", deliveryKey: "nul", data: { ...input.data, title: "bad\u0000title" } }],
          evidence,
        );
        assert.equal(badText.action, "quarantined");
        assert.ok(badText.issues.includes("invalid_unicode"));
      },
    );
    await t.test("unresolved venues are retained without creating users", async () => {
      const [result] = await recordObservations(
        pool,
        [{ ...input, sourceKey: "missing-venue", deliveryKey: "missing-venue", venueId: "gone" }],
        evidence,
      );
      assert.equal(result.action, "inserted");
      const event = (
        await pool.query("SELECT venue_id,original_venue_id,publication_state FROM scraped_events WHERE event_id=$1", [
          result.event_id,
        ])
      ).rows[0];
      assert.deepEqual(event, { venue_id: null, original_venue_id: "gone", publication_state: "unpublished" });
      const [conflict] = await recordObservations(
        pool,
        [{ ...input, deliveryKey: "venue-conflict", observedAt: "2020-01-04T00:00:00Z", venueId: "artist" }],
        evidence,
      );
      assert.equal(conflict.action, "quarantined");
      assert.deepEqual(conflict.issues, ["venue_conflict"]);
    });
    await t.test("malformed facts and history remain recoverable without new canonical events", async () => {
      const [bad] = await recordObservations(
        pool,
        [{ ...input, sourceKey: "bad", deliveryKey: "bad", data: { ...input.data, startTime: "bad" } }],
        evidence,
      );
      assert.equal(bad.action, "quarantined");
      assert.equal(bad.event_id, null);
      await pool.query("INSERT INTO scrape_runs(id,scraper_id) VALUES('missing-user-run','nonexistent-user')");
      const [history] = await recordObservations(
        pool,
        [
          {
            ...input,
            source: "legacy-scrapers",
            sourceKey: "old-url",
            deliveryKey: "history",
            runId: "missing-user-run",
            materialize: false,
          },
        ],
        evidence,
      );
      assert.equal(history.action, "archived");
      assert.equal(history.event_id, null);
      const objectId = await registerEvidence(pool, evidence);
      const bypass = await pool.query("SELECT * FROM record_scrape_observations($1::jsonb)", [
        JSON.stringify([
          {
            ...input,
            sourceKey: "bypass",
            deliveryKey: "bypass",
            evidenceId: objectId,
            facts: { performers: [], prices: [], startTime: "infinity" },
            errors: [],
          },
        ]),
      ]);
      assert.equal(bypass.rows[0].action, "quarantined");
    });
    await t.test(
      "least-privilege producers can capture, but cannot create bookings/profiles or rewrite observations",
      async () => {
        const client = await pool.connect();
        // Pool.query discards failed connections, which would lose SET ROLE between assertions.
        const producer = { query: client.query.bind(client) } as unknown as Pool;
        await client.query("SET ROLE tapped_ingestion");
        try {
          assert.equal(
            (await recordObservations(producer, [{ ...input, sourceKey: "role", deliveryKey: "role" }], evidence))[0]
              .action,
            "inserted",
          );
          await assert.rejects(client.query("INSERT INTO bookings(id) VALUES('forbidden')"), /permission denied/);
          await assert.rejects(client.query("UPDATE scrape_results SET payload='{}'"), /permission denied/);
          await assert.rejects(
            client.query("SELECT ingest_scraped_event('test','key','venue','{}')"),
            /permission denied/,
          );
          await assert.rejects(client.query("SELECT ingest_unclaimed_artist('name')"), /permission denied/);
          await assert.rejects(
            client.query("UPDATE scraped_events SET publication_state='published'"),
            /permission denied/,
          );
        } finally {
          await client.query("RESET ROLE");
          client.release();
        }
      },
    );
    await t.test("leased work is bounded and stale acknowledgements fail", async () => {
      await pool.query(
        "INSERT INTO scrape_targets(source,source_key,url) VALUES('test','target','https://example.test')",
      );
      const claimed = (await pool.query("SELECT * FROM claim_scrape_targets(1,30)")).rows;
      assert.equal(claimed.length, 1);
      assert.equal((await pool.query("SELECT * FROM claim_scrape_targets(1,30)")).rowCount, 0);
      assert.equal(
        (
          await pool.query("SELECT finish_scrape_target($1,$2,now()+interval '1 hour') AS ok", [
            claimed[0].id,
            randomUUID(),
          ])
        ).rows[0].ok,
        false,
      );
      assert.equal(
        (
          await pool.query("SELECT finish_scrape_target($1,$2,now()+interval '1 hour') AS ok", [
            claimed[0].id,
            claimed[0].lease_token,
          ])
        ).rows[0].ok,
        true,
      );
    });
  } finally {
    await pool.end();
    await admin.query(`DROP DATABASE ${name} WITH (FORCE)`);
    await admin.end();
  }
});

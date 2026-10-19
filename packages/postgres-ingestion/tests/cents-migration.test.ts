import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { Pool } from "pg";
import { normalizeObservation, recordObservations, registerEvidence, withFormattingV2 } from "../src/observations";

const url = process.env.INGESTION_TEST_DATABASE_URL;
test("populated cents migration, immutable v1 replay and versioned cleanup", { skip: !url }, async () => {
  const base = new URL(url as string);
  assert.ok(["127.0.0.1", "localhost"].includes(base.hostname));
  const admin = new Pool({ connectionString: base.href, max: 1 });
  const name = `cents_${randomUUID().replaceAll("-", "")}`;
  await admin.query(`CREATE DATABASE ${name}`);
  base.pathname = `/${name}`;
  const pool = new Pool({ connectionString: base.href, max: 1 });
  try {
    const folder = resolve(__dirname, "../../../services/api.tapped.ai/migrations");
    const files = (await readdir(folder)).filter((f) => f.endsWith(".sql")).sort();
    for (const file of files.filter((f) => f < "20261029000000"))
      await pool.query(await readFile(resolve(folder, file), "utf8"));
    await pool.query(`INSERT INTO users(id,username,profile) VALUES('venue','venue','{}'),('artist','artist','{}');
      INSERT INTO bookings(id,requester_id,requestee_id,status) VALUES('native-booking','venue','artist','confirmed');
      INSERT INTO scraped_events(source,source_key,venue_id,event_id,payload) VALUES('event-crawler','existing','venue','preserved-money-id','{"legacyBaseline":true}');`);
    const evidence = {
      bucket: "private-cents-test",
      key: `archive/aa/${"a".repeat(64)}.gz`,
      sha256: "a".repeat(64),
      bytes: 100,
      contentType: "application/x-ndjson",
      contentEncoding: "gzip" as const,
    };
    const legacy = {
      source: "event-crawler",
      sourceKey: "existing",
      deliveryKey: "zz-legacy",
      parserVersion: "fixture-v1",
      observedAt: "2020-01-01T00:00:00.123456Z",
      venueId: "venue",
      data: {
        title: "Show",
        startTime: "2030-01-01T20:00:00Z",
        isMusicEvent: true,
        artists: ["Artist"],
        ticketPrice: 1.01,
      },
    };
    const original = (await recordObservations(pool, [legacy], evidence))[0];
    const originalPayload = (
      await pool.query("SELECT payload FROM scrape_results WHERE id=$1", [original.observation_id])
    ).rows[0].payload;
    const dirty = {
      ...legacy,
      sourceKey: "dirty",
      deliveryKey: "dirty-v1",
      data: { ...legacy.data, artists: ["", " Artist ", " "], flierUrl: "N/A", ticketPrice: 0.29 },
    };
    const oldQuarantine = (await recordObservations(pool, [dirty], evidence))[0];
    assert.equal(oldQuarantine.action, "quarantined");
    const native = async () =>
      (
        await pool.query(
          "SELECT (SELECT md5(jsonb_agg(to_jsonb(u) ORDER BY id)::text) FROM users u) AS users,(SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) FROM bookings b) AS bookings",
        )
      ).rows[0];
    const before = await native();
    const migration = await readFile(resolve(folder, "20261029000000_scrape_money_cents.sql"), "utf8");
    await pool.query("UPDATE event_prices SET currency='EUR'");
    await assert.rejects(pool.query(migration), /non-USD/);
    await pool.query("UPDATE event_prices SET currency=NULL,amount_min=1.005,amount_max=1.005");
    await assert.rejects(pool.query(migration), /Fractional cents/);
    await pool.query("UPDATE event_prices SET amount_min=1.01,amount_max=1.01");
    await pool.query(migration);
    const price = (await pool.query("SELECT amount_min_cents,amount_max_cents,currency FROM event_prices")).rows[0];
    assert.deepEqual(price, { amount_min_cents: "101", amount_max_cents: "101", currency: "USD" });
    assert.deepEqual(
      (await pool.query("SELECT payload FROM scrape_results WHERE id=$1", [original.observation_id])).rows[0].payload,
      originalPayload,
    );
    const projection = (await pool.query("SELECT payload FROM scraped_events WHERE event_id='preserved-money-id'"))
      .rows[0].payload;
    assert.equal(projection.priceUnit, "usd_cent");
    assert.equal(projection.prices[0].amountMinCents, 101);
    assert.ok(!("amountMin" in projection.prices[0]));
    const v2 = { ...withFormattingV2(legacy, "usd_major"), deliveryKey: "0-v2" };
    const current = (await recordObservations(pool, [v2], evidence))[0];
    assert.equal(current.action, "updated", "same-capture v2 must beat v1 even with a smaller delivery key");
    assert.equal(current.event_id, "preserved-money-id");
    assert.equal((await recordObservations(pool, [v2], evidence))[0].action, "duplicate");
    assert.equal((await recordObservations(pool, [legacy], evidence))[0].action, "duplicate");
    const lateLegacy = { ...legacy, deliveryKey: "zzz-late-legacy" };
    assert.equal((await recordObservations(pool, [lateLegacy], evidence))[0].action, "historical");
    assert.equal(
      (await pool.query("SELECT current_observation_id FROM scraped_events WHERE event_id='preserved-money-id'"))
        .rows[0].current_observation_id,
      current.observation_id,
    );
    const fixed = (await recordObservations(pool, [withFormattingV2(dirty, "usd_major")], evidence))[0];
    assert.equal(fixed.action, "inserted");
    const cleaned = (
      await pool.query(
        "SELECT payload,normalization_version,input_price_unit,normalization_notes FROM scrape_results WHERE id=$1",
        [fixed.observation_id],
      )
    ).rows[0];
    assert.deepEqual(cleaned.payload.performers, ["Artist"]);
    assert.equal(cleaned.payload.flierUrl, null);
    assert.equal(cleaned.payload.prices[0].amountMinCents, 29);
    assert.equal(cleaned.normalization_version, 2);
    assert.equal(cleaned.input_price_unit, "usd_major");
    assert.ok(cleaned.normalization_notes.includes("empty_performer_omitted"));
    assert.equal(
      (await pool.query("SELECT processing_state FROM scrape_results WHERE id=$1", [oldQuarantine.observation_id]))
        .rows[0].processing_state,
      "quarantined",
    );
    const conflict = withFormattingV2({ ...legacy, deliveryKey: "different-venue", venueId: "artist" }, "usd_major");
    assert.equal((await recordObservations(pool, [conflict], evidence))[0].action, "quarantined");
    const newerLegacy = {
      ...legacy,
      deliveryKey: "newer-capture",
      observedAt: "2020-01-02T00:00:00Z",
      data: { ...legacy.data, ticketPrice: 2.99 },
    };
    assert.equal((await recordObservations(pool, [newerLegacy], evidence))[0].action, "updated");
    assert.equal(
      (await pool.query("SELECT amount_min_cents FROM event_prices WHERE event_id='preserved-money-id'")).rows[0]
        .amount_min_cents,
      "299",
    );
    const evidenceId = await registerEvidence(pool, evidence);
    const bypass = {
      ...normalizeObservation(v2),
      deliveryKey: "fractional-bypass",
      sourceKey: "fractional-bypass",
      evidenceId,
      errors: [],
      facts: {
        ...normalizeObservation(v2).facts,
        prices: [{ kind: "ticket", amountMinCents: 1.5, amountMaxCents: 1.5, currency: "USD" }],
      },
    };
    assert.equal(
      (await pool.query("SELECT * FROM record_scrape_observations($1::jsonb)", [JSON.stringify([bypass])])).rows[0]
        .action,
      "quarantined",
    );
    const history = withFormattingV2(
      { ...dirty, source: "legacy-scrapers", sourceKey: "history", deliveryKey: "history", materialize: false },
      "usd_major",
    );
    assert.equal((await recordObservations(pool, [history], evidence))[0].action, "archived");
    assert.equal(
      (await pool.query("SELECT count(*) FROM scraped_events WHERE source='legacy-scrapers'")).rows[0].count,
      "0",
    );
    assert.deepEqual(await native(), before);
    assert.equal((await pool.query("SELECT count(*) FROM external_effect_outbox")).rows[0].count, "0");
    assert.equal(
      (await pool.query("SELECT count(*) FROM scraped_events WHERE publication_state='published'")).rows[0].count,
      "0",
    );
  } finally {
    await pool.end();
    await admin.query(`DROP DATABASE ${name} WITH (FORCE)`);
    await admin.end();
  }
});

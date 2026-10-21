import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import { Pool } from "pg";
import { recordObservations, withFormattingV2, withVenueResolution } from "../src/observations";

const url = process.env.INGESTION_TEST_DATABASE_URL;
test(
  "reviewed venue compatibility is privileged, capture-scoped and preserves all identities",
  { skip: !url },
  async () => {
    const base = new URL(url as string);
    assert.ok(["127.0.0.1", "localhost"].includes(base.hostname));
    const admin = new Pool({ connectionString: base.href, max: 1 });
    const name = `venue_review_${randomUUID().replaceAll("-", "")}`;
    await admin.query(`CREATE DATABASE ${name}`);
    base.pathname = `/${name}`;
    const pool = new Pool({ connectionString: base.href, max: 1 });
    try {
      const folder = resolve(__dirname, "../../../services/api.tapped.ai/migrations");
      for (const file of (await readdir(folder)).filter((f) => f.endsWith(".sql")).sort())
        await pool.query(await readFile(resolve(folder, file), "utf8"));
      await pool.query(`INSERT INTO users(id,username,artist_name,unclaimed,place_id,profile) VALUES
      ('preserved','preserved','Venue and Lounge',true,'same-place','{"venueInfo":{"websiteUrl":"https://venue.example/"}}'),
      ('source','source','Venue & Lounge',true,'same-place','{"venueInfo":{"websiteUrl":"https://venue.example/"}}'),
      ('artist','artist','Artist',true,NULL,'{}');
      INSERT INTO bookings(id,requester_id,requestee_id,status) VALUES('native','preserved','artist','confirmed');
      INSERT INTO scraped_events(source,source_key,venue_id,event_id,payload) VALUES
      ('event-crawler','existing','preserved','original-event-id','{"priceUnit":"usd_cent","prices":[]}'),
      ('event-crawler','drift','preserved','drift-event-id','{"priceUnit":"usd_cent","prices":[]}');`);
      const evidence = {
        bucket: "private-venue-test",
        key: `archive/aa/${"a".repeat(64)}.gz`,
        sha256: "a".repeat(64),
        bytes: 100,
        contentType: "application/x-ndjson",
        contentEncoding: "gzip" as const,
      };
      const baseInput = withFormattingV2(
        {
          source: "event-crawler",
          sourceKey: "existing",
          deliveryKey: "captured",
          parserVersion: "fixture-v1",
          observedAt: "2020-01-01T00:00:00.123456Z",
          venueId: "source",
          evidenceLine: 1,
          data: {
            title: "Show",
            startTime: "2030-01-01T20:00:00Z",
            isMusicEvent: true,
            artists: ["Artist", ""],
            flierUrl: "N/A",
            ticketPrice: 1.01,
          },
        },
        "usd_major",
      );
      const held = (await recordObservations(pool, [baseInput], evidence))[0];
      assert.equal(held.action, "quarantined");
      assert.deepEqual(held.issues, ["venue_conflict"]);
      const hashes = (
        await pool.query(
          "SELECT scrape_venue_identity_hash('source') AS source,scrape_venue_identity_hash('preserved') AS preserved",
        )
      ).rows[0];
      const proof = {
        kind: "same_place_site_name_variant",
        auditSha256: "b".repeat(64),
        sourceRootSha256: "c".repeat(64),
        sourceProfileSha256: hashes.source,
        preservedProfileSha256: hashes.preserved,
      };
      const approve = async (delivery = baseInput.deliveryKey, event = "original-event-id", p = proof) =>
        String(
          (
            await pool.query(
              "SELECT approve_scrape_venue_resolution('event-crawler',$1,$2,'preserved','source','fixture-review-v1',$3::jsonb) AS id",
              [delivery, event, JSON.stringify(p)],
            )
          ).rows[0].id,
        );
      const client = await pool.connect();
      await client.query("SET ROLE tapped_ingestion");
      try {
        await assert.rejects(
          client.query(
            "SELECT approve_scrape_venue_resolution('event-crawler',$1,'original-event-id','preserved','source','fixture-review-v1',$2::jsonb)",
            [baseInput.deliveryKey, JSON.stringify(proof)],
          ),
          /permission denied/,
        );
        await assert.rejects(
          client.query("INSERT INTO scrape_venue_resolutions(id) VALUES('forbidden')"),
          /permission denied/,
        );
      } finally {
        await client.query("RESET ROLE");
        client.release();
      }
      await assert.rejects(
        recordObservations(pool, [withVenueResolution(baseInput, `venue-resolution-${"0".repeat(64)}`)], evidence),
        /unapproved/,
      );
      const id = await approve();
      assert.equal(await approve(), id);
      await assert.rejects(approve(baseInput.deliveryKey, "wrong-event"), /preconditions/);
      await assert.rejects(
        approve(baseInput.deliveryKey, "original-event-id", { ...proof, auditSha256: "d".repeat(64) }),
        /collision/,
      );
      const reviewed = withVenueResolution(baseInput, id);
      assert.equal(reviewed.venueId, "source");
      assert.equal(reviewed.observedAt, baseInput.observedAt);
      assert.equal(reviewed.sourceKey, baseInput.sourceKey);
      assert.equal(reviewed.data, baseInput.data);
      assert.deepEqual(withVenueResolution(reviewed, id), reviewed);
      for (const changed of [
        { ...reviewed, sourceKey: "another-event" },
        { ...reviewed, observedAt: "2020-01-02T00:00:00Z" },
        { ...reviewed, venueId: "preserved" },
        { ...reviewed, evidenceLine: 2 },
        { ...reviewed, data: { ...reviewed.data, title: "Changed facts" } },
      ])
        await assert.rejects(recordObservations(pool, [changed], evidence), /scope or evidence changed/);
      const drift = { ...baseInput, sourceKey: "drift", deliveryKey: "drift-capture" };
      assert.equal((await recordObservations(pool, [drift], evidence))[0].action, "quarantined");
      const driftId = await approve(drift.deliveryKey, "drift-event-id");
      await pool.query("UPDATE users SET artist_name='Changed identity' WHERE id='source'");
      await assert.rejects(
        recordObservations(pool, [withVenueResolution(drift, driftId)], evidence),
        /scope or evidence changed/,
      );
      await pool.query("UPDATE users SET artist_name='Venue & Lounge' WHERE id='source'");
      await pool.query("UPDATE scrape_venue_resolutions SET revoked_at=now() WHERE id=$1", [driftId]);
      await assert.rejects(recordObservations(pool, [withVenueResolution(drift, driftId)], evidence), /unapproved/);
      const native = async () =>
        (
          await pool.query(
            "SELECT (SELECT md5(jsonb_agg(to_jsonb(u) ORDER BY id)::text) FROM users u) AS users,(SELECT md5(jsonb_agg(to_jsonb(b) ORDER BY id)::text) FROM bookings b) AS bookings",
          )
        ).rows[0];
      const before = await native();
      const accepted = (await recordObservations(pool, [reviewed], evidence))[0];
      assert.equal(accepted.action, "updated");
      assert.equal(accepted.event_id, "original-event-id");
      const projected = (
        await pool.query(
          "SELECT venue_id,original_venue_id,current_observation_id,publication_state FROM scraped_events WHERE event_id='original-event-id'",
        )
      ).rows[0];
      assert.deepEqual(projected, {
        venue_id: "preserved",
        original_venue_id: "source",
        current_observation_id: accepted.observation_id,
        publication_state: "unpublished",
      });
      const old = (
        await pool.query(
          "SELECT processing_state,validation_errors,venue_resolution_id FROM scrape_results WHERE id=$1",
          [held.observation_id],
        )
      ).rows[0];
      assert.deepEqual(old, {
        processing_state: "quarantined",
        validation_errors: ["venue_conflict"],
        venue_resolution_id: null,
      });
      assert.equal((await recordObservations(pool, [reviewed], evidence))[0].action, "duplicate");
      assert.equal((await recordObservations(pool, [baseInput], evidence))[0].action, "duplicate");
      const sameCapture = { ...baseInput, deliveryKey: "ordinary-same-capture" };
      assert.equal((await recordObservations(pool, [sameCapture], evidence))[0].action, "historical");
      const laterCapture = { ...baseInput, deliveryKey: "ordinary-new-capture", observedAt: "2020-01-02T00:00:00Z" };
      assert.equal(
        (await recordObservations(pool, [laterCapture], evidence))[0].action,
        "quarantined",
        "review must not become a global venue alias",
      );
      assert.deepEqual(await native(), before);
      assert.equal(
        (await pool.query("SELECT amount_min_cents FROM event_prices WHERE event_id='original-event-id'")).rows[0]
          .amount_min_cents,
        "101",
      );
      assert.equal((await pool.query("SELECT count(*) FROM external_effect_outbox")).rows[0].count, "0");
    } finally {
      await pool.end();
      await admin.query(`DROP DATABASE ${name} WITH (FORCE)`);
      await admin.end();
    }
  },
);

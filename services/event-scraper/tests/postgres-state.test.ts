import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { describe, test } from "node:test";
import pg from "pg";
import {
  claimJob,
  consumeCounter,
  enqueueJob,
  getCandidate,
  getRawPage,
  listAlerts,
  one,
  openDb,
  raiseAlert,
  reserveHostSlot,
  run,
  transaction,
} from "../src/db.js";
import { importSqlite } from "../src/import-sqlite.js";
import { DiskPageStore } from "../src/pages.js";
import { openTestDb, testDatabaseUrl } from "./helpers/db.js";

const T0 = Date.UTC(2026, 10, 5);

describe("shared state across processes", () => {
  test("concurrent workers never claim the same job", async () => {
    const db = await openTestDb();
    for (let i = 0; i < 10; i++) await enqueueJob(db, "fetch_source", { i }, { now: T0 });
    const other = await openDb({ url: testDatabaseUrl(), schema: db.schema, maxConnections: 3, idleTimeoutMs: 100 });
    const claims = await Promise.all(Array.from({ length: 16 }, (_, i) => claimJob(i % 2 ? db : other, { now: T0 })));
    const ids = claims.flatMap((job) => (job ? [job.id] : []));
    assert.equal(ids.length, 10);
    assert.equal(new Set(ids).size, 10);
  });

  test("the daily counter never passes its cap, and host slots never collide", async () => {
    const db = await openTestDb();
    const consumed = await Promise.all(Array.from({ length: 12 }, () => consumeCounter(db, "llm", 5, T0)));
    assert.equal(consumed.filter(Boolean).length, 5);
    const slots = await Promise.all(Array.from({ length: 6 }, () => reserveHostSlot(db, "a.test", T0, 1000)));
    assert.deepEqual(
      [...slots].sort((a, b) => a - b),
      [T0, T0 + 1000, T0 + 2000, T0 + 3000, T0 + 4000, T0 + 5000],
    );
  });

  test("one open alert per kind and source, even when raised at once", async () => {
    const db = await openTestDb();
    await Promise.all(Array.from({ length: 5 }, () => raiseAlert(db, { kind: "fetch_failed", message: "x" }, T0)));
    assert.equal((await listAlerts(db, { open: true })).length, 1);
  });
});

describe("production role", () => {
  test("bootstrap gives the role its own schema and read-only access to the identifying columns", async () => {
    const database = `scraper_role_${randomBytes(6).toString("hex")}`;
    const adminUrl = new URL(testDatabaseUrl());
    const admin = new pg.Client({ connectionString: adminUrl.href });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${database}`);
    const ownerUrl = new URL(adminUrl);
    ownerUrl.pathname = `/${database}`;
    const owner = new pg.Client({ connectionString: ownerUrl.href });
    await owner.connect();
    try {
      await owner.query(`CREATE TABLE scraped_events (source text, source_key text, venue_id text, title text,
        start_time timestamptz, event_url text, music_classification text, payload jsonb);
        INSERT INTO scraped_events (source, source_key, payload) VALUES ('event-crawler', 'k', '{"private":true}');
        CREATE TABLE bookings (id text);
        CREATE VIEW ingestion_profiles AS SELECT 'venue-1'::text AS id;`);
      await owner.query(readFileSync(new URL("../sql/production-bootstrap.sql", import.meta.url), "utf8"));
      await owner.query("ALTER ROLE tapped_scraper PASSWORD 'local-test-only'");
      const url = new URL(ownerUrl);
      url.username = "tapped_scraper";
      url.password = "local-test-only";

      const db = await openDb({ url: url.href, maxConnections: 2, idleTimeoutMs: 100 });
      assert.equal(db.schema, "scraper");
      await enqueueJob(db, "fetch_source", {}, { now: T0 });
      assert.equal((await one(db, "SELECT source FROM scraped_events"))?.source, "event-crawler");
      assert.equal((await one(db, "SELECT id FROM ingestion_profiles"))?.id, "venue-1");
      const denied = /permission denied/;
      await assert.rejects(() => one(db, "SELECT payload FROM scraped_events"), denied);
      await assert.rejects(() => run(db, "UPDATE scraped_events SET title='x'"), denied);
      await assert.rejects(() => run(db, "DELETE FROM scraped_events"), denied);
      await assert.rejects(() => run(db, "INSERT INTO scraped_events (source) VALUES ('x')"), denied);
      await assert.rejects(() => one(db, "SELECT * FROM bookings"), denied);
      await assert.rejects(() => run(db, "CREATE TABLE public.nope (x int)"), denied);
      await db.close();

      await owner.query(readFileSync(new URL("../sql/production-rollback.sql", import.meta.url), "utf8"));
      const left = await owner.query("SELECT 1 FROM pg_roles WHERE rolname='tapped_scraper'");
      assert.equal(left.rowCount, 0);
      assert.equal((await owner.query("SELECT COUNT(*)::int AS n FROM scraped_events")).rows[0].n, 1);
    } finally {
      // Cleanup failures must not leave a connection open: that would hang the whole test run.
      await owner.end().catch(() => undefined);
      await admin
        .query(`DROP DATABASE ${database} WITH (FORCE)`)
        .then(() => admin.query("DROP ROLE IF EXISTS tapped_scraper"))
        .finally(() => admin.end());
    }
  });
});

describe("writer lock", () => {
  test("a transaction waits for the lock past the role's timeouts, then gets them back", async () => {
    const db = await openTestDb();
    const outside = await one(
      db,
      "SELECT current_setting('lock_timeout') AS lock, current_setting('statement_timeout') AS st",
    );
    let release: () => void = () => undefined;
    const holding = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = transaction(db, () => holding);
    await new Promise((resolve) => setTimeout(resolve, 100));
    const second = transaction(db, () =>
      one(db, "SELECT current_setting('lock_timeout') AS lock, current_setting('statement_timeout') AS st"),
    );
    await new Promise((resolve) => setTimeout(resolve, 100));
    release();
    await first;
    assert.deepEqual(await second, outside);
    await db.close();
  });
});

describe("lost connection", () => {
  test("a connection dropped mid-transaction fails that transaction, not the process, and the next one works", async () => {
    const db = await openTestDb();
    await assert.rejects(
      transaction(db, async () => {
        const row = await one(db, "SELECT pg_backend_pid() AS pid");
        await db.pool.query("SELECT pg_terminate_backend($1)", [row?.pid]);
        await new Promise((resolve) => setTimeout(resolve, 200));
        await one(db, "SELECT 1");
      }),
    );
    assert.equal((await one(db, "SELECT 1 AS ok"))?.ok, 1);
    await db.close();
  });
});

describe("import-sqlite", () => {
  test("copies state with ids, converts flags and JSON, and new ids continue after the copied ones", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-import-"));
    try {
      const path = join(dir, "old.sqlite");
      const old = new DatabaseSync(path);
      old.exec(`
        CREATE TABLE venues (id TEXT, name TEXT, address TEXT, lat REAL, lng REAL, website TEXT, google_place_id TEXT,
          timezone TEXT, synced_at INTEGER);
        CREATE TABLE sources (id TEXT, venue_id TEXT, kind TEXT, url TEXT, timezone TEXT, enabled INTEGER, label TEXT,
          origin TEXT, fetch_interval_ms INTEGER, created_at INTEGER, updated_at INTEGER);
        CREATE TABLE fetch_state (source_id TEXT);
        CREATE TABLE raw_pages (sha256 TEXT, url TEXT, content_type TEXT, size INTEGER, bytes BLOB, first_seen_at INTEGER);
        CREATE TABLE jobs (id INTEGER, kind TEXT);
        CREATE TABLE events (id INTEGER, source_id TEXT);
        CREATE TABLE event_changes (id INTEGER);
        CREATE TABLE alerts (id INTEGER);
        CREATE TABLE venue_candidates (id INTEGER, name TEXT, normalized_name TEXT, discovered_from TEXT, evidence TEXT,
          status TEXT, created_at INTEGER, updated_at INTEGER);
        CREATE TABLE venue_place_ids (place_id TEXT, candidate_id INTEGER, is_canonical INTEGER, types TEXT,
          created_at INTEGER, updated_at INTEGER);
        CREATE TABLE publish_outbox (id INTEGER);
        CREATE TABLE kv (key TEXT, value TEXT, updated_at INTEGER);
        CREATE TABLE host_slots (host TEXT);
        INSERT INTO venues (id, name, synced_at) VALUES ('v1', 'Room', 1);
        INSERT INTO sources VALUES ('s1', 'v1', 'html', 'https://a.test/', 'UTC', 0, NULL, 'manual', 1000, 1, 1);
        INSERT INTO venue_candidates VALUES (41, 'Room', 'room', 'osm', '{"a":1}', 'promoted', 1, 1);
        INSERT INTO venue_place_ids VALUES ('p1', 41, 1, '["bar"]', 1, 1);
        INSERT INTO kv VALUES ('feed:osm', '123', 1);
      `);
      old
        .prepare("INSERT INTO raw_pages VALUES (?, 'https://a.test/', 'text/html', 2, ?, 1)")
        .run("a".repeat(64), new Uint8Array([104, 105]));
      old.close();

      const db = await openTestDb();
      const target = await openDb({
        url: testDatabaseUrl(),
        schema: db.schema,
        pages: new DiskPageStore(join(dir, "pages")),
        maxConnections: 2,
        idleTimeoutMs: 100,
      });
      const first = await importSqlite(target, path);
      assert.deepEqual(
        [first.venues, first.sources, first.venue_candidates, first.venue_place_ids, first.kv, first.raw_pages],
        [1, 1, 1, 1, 1, 1],
      );
      const candidate = await getCandidate(target, 41);
      assert.deepEqual(candidate?.evidence, { a: 1 });
      assert.equal((await one(target, "SELECT enabled FROM sources"))?.enabled, false);
      const alias = await one(target, "SELECT is_canonical, types FROM venue_place_ids");
      assert.deepEqual([alias?.is_canonical, alias?.types], [true, ["bar"]]);
      assert.deepEqual([...((await getRawPage(target, "a".repeat(64)))?.bytes ?? [])], [104, 105]);
      const next = await one(target, "SELECT nextval(pg_get_serial_sequence('venue_candidates','id')) AS id");
      assert.equal(next?.id, 42);
      const again = await importSqlite(target, path);
      assert.equal(again.venue_candidates, 0, "a second import changes nothing");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { captureObservations, deliveryKey, normalizeFacts, normalizeObservation, timestamp } from "../src/observations";

const data = { startTime: "2030-01-01T20:00:00Z", artists: [" Nova ", "Nova"], ticketPrice: 0, isMusicEvent: false };
const input = {
  source: "test",
  sourceKey: "url",
  deliveryKey: "delivery",
  observedAt: "2020-01-01T00:00:00Z",
  parserVersion: "v1",
  data,
};
test("normalization retains unknowns, free prices, legacy artists, and non-music classification", () => {
  const { facts, errors } = normalizeFacts({ ...data, venue: { email: "private@test.invalid" }, bookingCount: 99 });
  assert.deepEqual(errors, []);
  assert.deepEqual(facts.performers, ["Nova"]);
  assert.equal(facts.musicClassification, "non_music");
  assert.equal(facts.endTime, null);
  assert.equal(facts.prices[0].amountMin, 0);
  assert.equal(facts.prices[0].currency, null);
  assert.ok(!JSON.stringify(facts).includes("private@test.invalid"));
  assert.equal(normalizeFacts({ startTime: data.startTime }).facts.musicClassification, "unknown");
});
test("messy facts are quarantinable, not fabricated or silently dropped", () => {
  for (const patch of [
    { startTime: null },
    { startTime: "tomorrow" },
    { startTime: "2030-01-01" },
    { endTime: "2020-01-01T00:00:00Z" },
    { performers: [123] },
    { ticketPrice: -1 },
    { doorPrice: Number.NaN },
    { flierUrl: "javascript:alert(1)" },
    { url: "https://user:pass@example.test" },
    { prices: [{ kind: "ticket", amountMin: 50, amountMax: 10, currency: "usd" }] },
  ])
    assert.ok(normalizeFacts({ ...data, isMusicEvent: true, ...patch }).errors.length > 0);
  assert.equal(timestamp(null), null);
  assert.equal(timestamp({ toDate: () => new Date("2030-01-01T00:00:00Z") }), "2030-01-01T00:00:00.000Z");
});
test("negative page classifications do not require fictional event dates", () => {
  const result = normalizeFacts({ isMusicEvent: false, url: "https://example.test/not-an-event" });
  assert.deepEqual(result.errors, []);
  assert.equal(result.facts.startTime, null);
  assert.equal(result.facts.musicClassification, "non_music");
});
test("NUL and malformed Unicode are quarantined without breaking a whole Postgres batch", () => {
  const result = normalizeFacts({ ...data, title: "bad\u0000title\uD800", description: String.raw`\u0000` });
  assert.ok(result.errors.includes("invalid_unicode"));
  assert.equal(result.facts.title, "bad\uFFFDtitle\uFFFD");
  assert.equal(result.facts.description, String.raw`\u0000`);
});
test("observation identities are explicit and namespace-safe", () => {
  assert.equal(normalizeObservation(input).sourceKey, "url");
  assert.throws(() => normalizeObservation({ ...input, source: "" }));
  assert.throws(() => normalizeObservation({ ...input, observedAt: "2100-01-01T00:00:00Z" }));
  assert.notEqual(deliveryKey("a:b", "c"), deliveryKey("a", "b:c"));
});
test("failed evidence upload cannot write database references", async () => {
  let queries = 0;
  const pool = {
    query: async () => {
      queries++;
    },
  } as unknown as Pool;
  await assert.rejects(
    captureObservations(
      pool,
      {
        put: async () => {
          throw new Error("upload failed");
        },
      },
      [input],
      Buffer.from("raw"),
    ),
    /upload failed/,
  );
  assert.equal(queries, 0);
});
test("invalid envelopes and oversized batches fail before uploading", async () => {
  let uploads = 0;
  const store = {
    put: async () => {
      uploads++;
      throw new Error("unexpected upload");
    },
  };
  const pool = {} as Pool;
  await assert.rejects(captureObservations(pool, store, [], Buffer.alloc(0)));
  await assert.rejects(captureObservations(pool, store, [{ ...input, deliveryKey: "" }], Buffer.from("raw")));
  assert.equal(uploads, 0);
});

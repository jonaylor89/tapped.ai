import assert from "node:assert/strict";
import test from "node:test";
import { firestoreObservation, firestoreRunId } from "../src/firestore-crawler";
import { normalizeObservation } from "../src/observations";

const document = {
  path: "crawler/https%3A%2F%2Fexample.test%2Fevent",
  version: "123:456",
  updatedAt: "2020-01-01T00:00:00Z",
  data: {
    title: "Show",
    startTime: { toDate: () => new Date("2030-01-01T20:00:00Z") },
    artists: ["Artist"],
    venue: { id: "missing-venue", email: "private@example.test" },
    crawlerInfo: { runId: "old", timestamp: "2010-01-01T00:00:00Z" },
  },
};
test("crawler imports preserve keys, use source update ordering, and are deterministic across batch layouts", () => {
  const first = firestoreObservation("project", document, 1);
  const repeated = firestoreObservation("project", document, 20);
  assert.equal(first.sourceKey, "https%3A%2F%2Fexample.test%2Fevent");
  assert.equal(first.deliveryKey, repeated.deliveryKey);
  assert.equal(first.observedAt, document.updatedAt);
  assert.equal(first.venueId, "missing-venue");
  assert.equal(first.runId, null);
  assert.equal(first.legacyRunId, "old");
  assert.ok(first.materialize);
  assert.notEqual(first.deliveryKey, firestoreObservation("other-project", document, 1).deliveryKey);
  assert.notEqual(
    first.deliveryKey,
    firestoreObservation("project", { ...document, version: "123:457" }, 1).deliveryKey,
  );
  assert.ok(!JSON.stringify(normalizeObservation(first).facts).includes("private@example.test"));
});
test("historical result imports keep orphaned runs without creating duplicate current events", () => {
  const input = firestoreObservation(
    "project",
    { ...document, path: "rawScrapeData/deleted-scraper/scrapeRuns/run/scrapeResults/result" },
    1,
  );
  assert.equal(input.materialize, false);
  assert.equal(input.source, "legacy-scrapers");
  assert.equal(input.venueId, "deleted-scraper");
  assert.equal(input.runId, firestoreRunId("project", "rawScrapeData/deleted-scraper/scrapeRuns/run"));
  assert.deepEqual(normalizeObservation(input).facts.performers, ["Artist"]);
  const long = firestoreObservation(
    "project",
    {
      ...document,
      path: "rawScrapeData/a/scrapeRuns/b/scrapeResults/c",
      data: { url: `https://example.test/${"x".repeat(5000)}` },
    },
    1,
  );
  assert.match(long.sourceKey, /^url-sha256:/);
  assert.throws(() => firestoreObservation("project", { ...document, path: "users/a" }, 1));
});

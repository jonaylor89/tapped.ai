import assert from "node:assert/strict";
import test from "node:test";
import { usdCents } from "../src/formatting-v2";
import { normalizeFacts, normalizeFactsV2, normalizeObservation, withFormattingV2 } from "../src/observations";

const data = {
  startTime: "2030-01-01T20:00:00Z",
  isMusicEvent: true,
  artists: [" Known artist ", "", "  ", "Known artist"],
  ticketPrice: 1.01,
  doorPrice: "20.00",
  flierUrl: "N/A",
  url: " n/a ",
};
const input = {
  source: "event-crawler",
  sourceKey: "original-key",
  deliveryKey: "original-delivery",
  observedAt: "2020-01-01T00:00:00.123456Z",
  parserVersion: "extract-v1",
  venueId: "original-venue",
  materialize: true,
  data,
};

test("approved cleanup omits blanks and URL placeholders without inventing names or destinations", () => {
  const before = JSON.stringify(data);
  const result = normalizeFactsV2(data, "usd_major");
  assert.deepEqual(result.errors, []);
  assert.deepEqual(result.facts.performers, ["Known artist"]);
  assert.equal(result.facts.url, null);
  assert.equal(result.facts.flierUrl, null);
  assert.equal(result.facts.priceUnit, "usd_cent");
  assert.deepEqual(
    result.facts.prices.map((p) => [p.amountMinCents, p.amountMaxCents, p.currency]),
    [
      [101, 101, "USD"],
      [2000, 2000, "USD"],
    ],
  );
  assert.ok(result.normalizationNotes.includes("empty_performer_omitted"));
  assert.ok(result.normalizationNotes.includes("usd_assumed"));
  assert.equal(JSON.stringify(data), before);
  const empty = normalizeFactsV2({ ...data, artists: ["", " "] }, "usd_major");
  assert.deepEqual(empty.facts.performers, []);
  assert.equal(empty.facts.musicClassification, "music");
});
test("USD conversion uses exact decimal cents, including binary float edge cases", () => {
  for (const [major, cents] of [
    [1, 100],
    [0, 0],
    [0.29, 29],
    [1.01, 101],
    [19.99, 1999],
    ["001.20", 120],
    ["1.2300", 123],
    [9999999999.99, 999999999999],
  ] as const)
    assert.equal(usdCents(major, "usd_major"), cents);
  assert.equal(usdCents(null, "usd_major"), null);
  assert.equal(usdCents(100, "usd_cent"), 100);
  assert.equal(usdCents("100", "usd_cent"), 100);
  for (const value of [-1, Number.NaN, Number.POSITIVE_INFINITY, true, "Free", "N/A", "$20", "1e2", "", "20,00", 1e10])
    assert.throws(() => usdCents(value, "usd_major"));
  assert.throws(() => usdCents(1.005, "usd_major"), /Fractional cent/);
  assert.throws(() => usdCents(1e-7, "usd_major"), /Fractional cent/);
  assert.throws(() => usdCents(1.5, "usd_cent"), /Fractional cent/);
});
test("explicit units and stable versioned identities prevent double multiplication and v1 collisions", () => {
  const v2 = withFormattingV2(input, "usd_major");
  assert.notEqual(v2.deliveryKey, input.deliveryKey);
  assert.equal(v2.sourceKey, input.sourceKey);
  assert.equal(v2.observedAt, input.observedAt);
  assert.equal(v2.venueId, input.venueId);
  assert.equal(v2.data, input.data);
  assert.equal(v2.normalizationVersion, 2);
  assert.deepEqual(withFormattingV2(v2, "usd_major"), v2);
  assert.throws(() => withFormattingV2(v2, "usd_cent"), /mismatch/);
  assert.throws(() => normalizeObservation({ ...input, normalizationVersion: 2 }), /Explicit/);
  assert.throws(() => normalizeObservation({ ...input, inputPriceUnit: "usd_major" }), /version 2/);
  assert.throws(() => normalizeFactsV2({ ...data, priceUnit: "usd_cent" }, "usd_major"), /mismatch/);
  assert.throws(() => normalizeObservation({ ...input, data: { ...data, priceUnit: "usd_cent" } }), /version 2/);
  assert.throws(
    () => normalizeObservation({ ...input, data: { prices: [{ kind: "ticket", amountMinCents: 100 }] } }),
    /version 2/,
  );
  const cents = normalizeFactsV2({ ...data, ticketPrice: 100, doorPrice: null, priceUnit: "usd_cent" }, "usd_cent");
  assert.equal(cents.facts.prices[0].amountMinCents, 100);
});
test("structured cents stay cents and incompatible currency, ambiguity and malformed values stay held", () => {
  const result = normalizeFactsV2(
    {
      ...data,
      ticketPrice: null,
      doorPrice: null,
      priceUnit: "usd_cent",
      prices: [{ kind: "ticket", amountMinCents: 100, amountMaxCents: 250, currency: "USD" }],
    },
    "usd_cent",
  );
  assert.deepEqual(result.errors, []);
  assert.equal(result.facts.prices[0].amountMinCents, 100);
  assert.throws(() => normalizeFactsV2({ prices: [{ kind: "ticket", amountMinCents: 100 }] }, "usd_major"), /mismatch/);
  for (const [patch, error] of [
    [{ artists: ["", 12] }, "invalid_performer"],
    [{ artists: "Known artist" }, "invalid_performers"],
    [{ artists: ["a".repeat(201)] }, "invalid_performer"],
    [{ flierUrl: "//cdn.example.test/image.png" }, "invalid_flier_url"],
    [{ url: "https://user:secret@example.test" }, "invalid_url"],
    [{ ticketPrice: -1 }, "invalid_price"],
    [{ ticketPrice: 1.005 }, "fractional_cent"],
    [{ currency: "EUR" }, "unsupported_currency"],
    [{ endTime: "2020-01-01T00:00:00Z" }, "reversed_times"],
  ] as const)
    assert.ok(normalizeFactsV2({ ...data, ...patch }, "usd_major").errors.includes(error));
});
test("strict v1 remains replayable; history still cannot materialize events", () => {
  assert.ok(normalizeFacts(data).errors.includes("invalid_performer"));
  assert.ok(normalizeFacts(data).errors.includes("invalid_flier_url"));
  const original = { ...input, data: { ...data, artists: ["Artist"], url: null, flierUrl: null, doorPrice: 20 } };
  const legacy = normalizeObservation(original);
  assert.equal(legacy.facts.prices[0].currency, null);
  assert.ok(!("priceUnit" in legacy.facts));
  assert.ok(!("normalizationNotes" in legacy));
  assert.ok(!("normalizationVersion" in legacy));
  const history = withFormattingV2({ ...input, source: "legacy-scrapers", materialize: false }, "usd_major");
  assert.equal(normalizeObservation(history).materialize, false);
});

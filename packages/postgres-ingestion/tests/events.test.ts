import assert from "node:assert/strict";
import test from "node:test";
import { database, type EventFacts, eventPayload } from "../src/index";

const event: EventFacts = {
  isMusicEvent: true,
  performers: [" Nova ", "Nova"],
  startTime: "2026-12-01T20:00:00Z",
  endTime: "2026-12-01T22:00:00Z",
  ticketPrice: 25,
};
test("only public facts are persisted, with normalized dates and performers", () => {
  const payload = eventPayload({ ...event, venue: { email: "private@example.test" }, bookingCount: 999 } as EventFacts);
  assert.deepEqual(payload, {
    isMusicEvent: true,
    performers: ["Nova"],
    startTime: "2026-12-01T20:00:00.000Z",
    endTime: "2026-12-01T22:00:00.000Z",
    title: null,
    description: null,
    url: null,
    flierUrl: null,
    runId: null,
    ticketPrice: 25,
    doorPrice: null,
  });
});
test("malformed facts fail before database access", () => {
  for (const patch of [
    { startTime: "bad" },
    { endTime: "2020-01-01" },
    { performers: [""] },
    { performers: Array(101).fill("Nova") },
    { ticketPrice: -1 },
    { doorPrice: Number.NaN },
    { isMusicEvent: "false" },
  ])
    assert.throws(() => eventPayload({ ...event, ...patch } as EventFacts));
});
test("there is no Firestore or privileged credential fallback", () => {
  const previous = process.env.INGESTION_DATABASE_URL;
  delete process.env.INGESTION_DATABASE_URL;
  try {
    assert.throws(database, /INGESTION_DATABASE_URL is required/);
  } finally {
    if (previous !== undefined) process.env.INGESTION_DATABASE_URL = previous;
  }
});

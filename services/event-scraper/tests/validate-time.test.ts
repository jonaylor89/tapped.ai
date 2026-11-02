import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  addDays,
  addMonths,
  instantToLocal,
  isValidTimeZone,
  localDate,
  localToUtc,
  parseInstant,
  parseLocal,
} from "../src/validate/time.js";
import { inferYear } from "../src/validate/validate.js";

describe("localToUtc DST handling", () => {
  test("ordinary times in NY, Chicago, LA (standard and daylight)", () => {
    assert.equal(localToUtc("2026-07-04T21:00", "America/New_York"), "2026-07-05T01:00:00.000Z");
    assert.equal(localToUtc("2026-12-04T21:00", "America/New_York"), "2026-12-05T02:00:00.000Z");
    assert.equal(localToUtc("2026-11-07T20:00", "America/Chicago"), "2026-11-08T02:00:00.000Z");
    assert.equal(localToUtc("2026-10-31T20:00", "America/Chicago"), "2026-11-01T01:00:00.000Z");
    assert.equal(localToUtc("2026-07-04T21:00", "America/Los_Angeles"), "2026-07-05T04:00:00.000Z");
    assert.equal(localToUtc("2027-01-09T21:00", "America/Los_Angeles"), "2027-01-10T05:00:00.000Z");
  });

  test("spring-forward gap pushes the time forward (2026-03-08)", () => {
    // 02:30 does not exist; compatible disambiguation -> 03:30 daylight time.
    assert.equal(localToUtc("2026-03-08T02:30", "America/New_York"), "2026-03-08T07:30:00.000Z");
    assert.equal(instantToLocal("2026-03-08T07:30:00.000Z", "America/New_York"), "2026-03-08T03:30");
    assert.equal(localToUtc("2026-03-08T02:30", "America/Chicago"), "2026-03-08T08:30:00.000Z");
    assert.equal(localToUtc("2026-03-08T02:30", "America/Los_Angeles"), "2026-03-08T10:30:00.000Z");
    // Just before and after the gap.
    assert.equal(localToUtc("2026-03-08T01:59", "America/New_York"), "2026-03-08T06:59:00.000Z");
    assert.equal(localToUtc("2026-03-08T03:00", "America/New_York"), "2026-03-08T07:00:00.000Z");
  });

  test("fall-back overlap resolves to the earlier instant (2026-11-01)", () => {
    assert.equal(localToUtc("2026-11-01T01:30", "America/New_York"), "2026-11-01T05:30:00.000Z");
    assert.equal(localToUtc("2026-11-01T01:30", "America/Chicago"), "2026-11-01T06:30:00.000Z");
    assert.equal(localToUtc("2026-11-01T01:30", "America/Los_Angeles"), "2026-11-01T08:30:00.000Z");
    // After the overlap the standard offset applies.
    assert.equal(localToUtc("2026-11-01T02:00", "America/New_York"), "2026-11-01T07:00:00.000Z");
    assert.equal(localToUtc("2026-11-01T00:30", "America/Los_Angeles"), "2026-11-01T07:30:00.000Z");
  });

  test("round trips every hour across both 2026 transitions", () => {
    for (const tz of ["America/New_York", "America/Chicago", "America/Los_Angeles"]) {
      for (const day of ["2026-03-07", "2026-03-08", "2026-03-09", "2026-10-31", "2026-11-01", "2026-11-02"]) {
        for (let h = 0; h < 24; h++) {
          const local = `${day}T${String(h).padStart(2, "0")}:15`;
          const utc = localToUtc(local, tz) as string;
          if (day === "2026-03-08" && h === 2) continue; // gap, covered above
          assert.equal(instantToLocal(utc, tz), local, `${tz} ${local}`);
        }
      }
    }
  });

  test("localDate uses the venue zone, not UTC", () => {
    const now = new Date("2026-11-03T04:30:00Z");
    assert.equal(localDate(now, "America/Los_Angeles"), "2026-11-02");
    assert.equal(localDate(now, "UTC"), "2026-11-03");
  });
});

describe("parsing helpers", () => {
  test("parseLocal shapes", () => {
    assert.equal(parseLocal("2026-11-07")?.kind, "date");
    assert.equal(parseLocal("2026-11-07T20:00")?.kind, "datetime");
    assert.equal(parseLocal("2026-11-07T20:00:30")?.kind, "datetime");
    assert.equal(parseLocal("--11-07")?.kind, "yearless");
    assert.equal(parseLocal("--02-29T19:00")?.kind, "yearless");
    assert.equal(parseLocal("20:30")?.kind, "time");
    assert.equal(parseLocal("2026-02-30"), null);
    assert.equal(parseLocal("2026-11-07T25:00"), null);
    assert.equal(parseLocal("next friday"), null);
  });

  test("parseInstant requires an offset", () => {
    assert.equal(parseInstant("2026-11-07T20:00:00-06:00"), Date.parse("2026-11-08T02:00:00Z"));
    assert.equal(parseInstant("2026-11-07T20:00:00-0600"), Date.parse("2026-11-08T02:00:00Z"));
    assert.equal(parseInstant("2026-11-08T02:00:00Z"), Date.parse("2026-11-08T02:00:00Z"));
    assert.equal(parseInstant("2026-11-07T20:00:00"), null);
  });

  test("calendar arithmetic", () => {
    assert.equal(addDays("2026-12-31", 1), "2027-01-01");
    assert.equal(addDays("2026-03-01", -1), "2026-02-28");
    assert.equal(addMonths("2026-01-31", 1), "2026-02-28");
    assert.equal(addMonths("2026-11-02", 13), "2027-12-02");
    assert.ok(isValidTimeZone("America/Chicago"));
    assert.ok(!isValidTimeZone("America/Nowhere"));
  });
});

describe("inferYear", () => {
  test("upcoming this year, rolled into next year, and yesterday's grace", () => {
    assert.equal(inferYear(11, 7, "2026-11-02"), 2026);
    assert.equal(inferYear(1, 9, "2026-11-02"), 2027);
    assert.equal(inferYear(11, 1, "2026-11-02"), 2026); // yesterday, within 1 day grace
    assert.equal(inferYear(10, 30, "2026-11-02"), 2027);
    assert.equal(inferYear(12, 31, "2027-01-01"), 2026); // New Year's Eve seen on New Year's Day
  });

  test("Feb 29 picks a leap year and weekday hints break ties", () => {
    assert.equal(inferYear(2, 29, "2027-03-05"), 2028);
    // Sat Jan 9 is 2027; a printed "Sat" keeps it there.
    assert.equal(inferYear(1, 9, "2026-11-02", { weekday: 6 }), 2027);
  });
});

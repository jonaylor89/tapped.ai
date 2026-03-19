import { describe, expect, it } from "vitest";
import { createEmailMessageId } from "./utils";

describe("createEmailMessageId", () => {
  it("returns a valid RFC 2822 Message-ID format", () => {
    const id = createEmailMessageId();
    expect(id).toMatch(/^<.+@tapped\.ai>$/);
  });

  it("generates unique IDs on successive calls", () => {
    const ids = new Set(Array.from({ length: 100 }, () => createEmailMessageId()));
    expect(ids.size).toBe(100);
  });

  it("contains a dot separating time and random parts", () => {
    const id = createEmailMessageId();
    const inner = id.slice(1, -1).split("@")[0];
    expect(inner).toContain(".");
    expect(inner.split(".")).toHaveLength(2);
  });
});

import { describe, expect, it } from "vitest";
import { formatTemplate } from "./openai";

describe("formatTemplate", () => {
  it("replaces single variable", () => {
    const result = formatTemplate("Hello {NAME}!", { NAME: "Alice" });
    expect(result).toBe("Hello Alice!");
  });

  it("replaces multiple variables", () => {
    const result = formatTemplate("{ARTIST} performing at {VENUE}", {
      ARTIST: "DJ Cool",
      VENUE: "The Roxy",
    });
    expect(result).toBe("DJ Cool performing at The Roxy");
  });

  it("replaces all occurrences of the same variable", () => {
    const result = formatTemplate("{NAME} is {NAME}", { NAME: "Bob" });
    expect(result).toBe("Bob is Bob");
  });

  it("leaves unmatched placeholders untouched", () => {
    const result = formatTemplate("{KNOWN} and {UNKNOWN}", { KNOWN: "yes" });
    expect(result).toBe("yes and {UNKNOWN}");
  });

  it("handles empty vars", () => {
    const result = formatTemplate("no vars here", {});
    expect(result).toBe("no vars here");
  });

  it("handles empty string values", () => {
    const result = formatTemplate("before {X} after", { X: "" });
    expect(result).toBe("before  after");
  });
});

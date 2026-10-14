import { createHmac } from "node:crypto";
import type { UserRecord } from "firebase-admin/auth";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("firebase-functions", () => ({
  runWith: () => ({ auth: { user: () => ({ onCreate: (fn: unknown) => fn, onDelete: (fn: unknown) => fn }) } }),
}));
vi.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "test-auth-hook-secret-at-least-32-chars" }),
}));

import { forwardAuthEvent } from "./auth_hooks";

const user = {
  uid: "synthetic-user",
  email: "synthetic@example.test",
  displayName: "Synthetic",
  metadata: { creationTime: "2026-10-01T00:00:00Z" },
} as UserRecord;

describe("transport-only Auth hooks", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    vi.stubEnv("TAPPED_API_URL", "https://api.test.invalid");
    fetchMock.mockResolvedValue(new Response(null, { status: 204 }));
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.clearAllMocks();
  });

  it.each([
    "signup",
    "delete",
  ] as const)("signs the exact %s payload and waits for durable acceptance", async (kind) => {
    await forwardAuthEvent(kind, user);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.test.invalid/webhooks/firebase/auth");
    const body = Buffer.from(options.body);
    expect(JSON.parse(body.toString())).toEqual({
      kind,
      account: {
        localId: user.uid,
        email: user.email,
        displayName: user.displayName,
        createdAt: String(Date.parse(user.metadata.creationTime)),
      },
    });
    const expected = createHmac("sha256", "test-auth-hook-secret-at-least-32-chars")
      .update(`${options.headers["x-tapped-timestamp"]}.`)
      .update(body)
      .digest("hex");
    expect(options.headers["x-tapped-signature"]).toBe(expected);
    expect(options.redirect).toBe("error");
  });
  it.each([
    400, 401, 429, 500, 503,
  ])("throws on HTTP %s so Firebase retries, without exposing API response", async (status) => {
    fetchMock.mockResolvedValue(new Response("private response", { status }));
    await expect(forwardAuthEvent("signup", user)).rejects.toThrow(`Auth lifecycle API HTTP ${status}`);
  });
  it("does not acknowledge network failure", async () => {
    fetchMock.mockRejectedValue(new Error("offline"));
    await expect(forwardAuthEvent("delete", user)).rejects.toThrow("offline");
  });
  it("rejects absent account incarnation rather than losing deduplication", async () => {
    await expect(
      forwardAuthEvent("signup", { ...user, metadata: { creationTime: "invalid" } } as UserRecord),
    ).rejects.toThrow("creation time unavailable");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

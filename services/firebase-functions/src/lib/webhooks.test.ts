import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("firebase-functions/v2/https", () => ({ onRequest: (_options: unknown, handler: unknown) => handler }));
vi.mock("firebase-functions/logger", () => ({ error: vi.fn() }));
vi.mock("./firebase", () => ({ MAIL_INGRESS_SECRET: { value: () => "test-ingress-secret" } }));

import { inboundEmailWebhook, streamBeforeMessageWebhook } from "./webhooks";

type Handler = (req: unknown, res: unknown) => Promise<void>;
function response() {
  const res = { status: vi.fn(), type: vi.fn(), send: vi.fn() };
  res.status.mockReturnValue(res);
  res.type.mockReturnValue(res);
  return res;
}
const rawBody = Buffer.from('{ "message": { "text": "héllo" } }\n');

describe("Rust webhook compatibility bridges", () => {
  const fetchMock = vi.fn();
  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
    vi.stubEnv("TAPPED_API_URL", "https://api.test.invalid/");
    fetchMock.mockResolvedValue(new Response('{"ok":true}', { headers: { "content-type": "application/json" } }));
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.clearAllMocks();
  });

  it("preserves Stream raw bytes/signature and delegates validation and response to Rust", async () => {
    const res = response();
    await (streamBeforeMessageWebhook as unknown as Handler)(
      { rawBody, headers: { "x-signature": "test-signature" } },
      res,
    );
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.test.invalid/webhooks/stream/before-message");
    expect(Buffer.from(options.body)).toEqual(rawBody);
    expect(options.headers["x-signature"]).toBe("test-signature");
    expect(options.redirect).toBe("error");
    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.send).toHaveBeenCalledWith('{"ok":true}');
  });

  it("does not forward an unsigned Stream request", async () => {
    const res = response();
    await (streamBeforeMessageWebhook as unknown as Handler)({ rawBody, headers: {} }, res);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("authenticates Postmark to Rust without embedding secrets in source/config", async () => {
    const res = response();
    await (inboundEmailWebhook as unknown as Handler)({ rawBody, headers: {} }, res);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.test.invalid/webhooks/postmark/inbound");
    expect(Buffer.from(options.body)).toEqual(rawBody);
    expect(options.headers.authorization).toBe(
      `Basic ${Buffer.from("postmark:test-ingress-secret").toString("base64")}`,
    );
  });

  it("propagates API rejection instead of acknowledging unsuccessful delivery", async () => {
    fetchMock.mockResolvedValue(new Response("invalid signature", { status: 403 }));
    const res = response();
    await (streamBeforeMessageWebhook as unknown as Handler)({ rawBody, headers: { "x-signature": "invalid" } }, res);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.send).toHaveBeenCalledWith("invalid signature");
  });

  it.each([
    inboundEmailWebhook,
    streamBeforeMessageWebhook,
  ])("returns 502 when the API is unreachable", async (handler) => {
    fetchMock.mockRejectedValue(new Error("offline"));
    const res = response();
    await (handler as unknown as Handler)({ rawBody, headers: { "x-signature": "test" } }, res);
    expect(res.status).toHaveBeenCalledWith(502);
  });
});

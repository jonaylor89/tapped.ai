import { createHmac } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ServerClient } from "./mail_client";

describe("ServerClient", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.TAPPED_API_URL;
  });

  it("forwards messages to the signed Tapped mail API", async () => {
    process.env.TAPPED_API_URL = "http://api.test";
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 202 }));
    vi.stubGlobal("fetch", fetchMock);
    const message = {
      From: "no-reply@tapped.ai",
      To: "fan@example.com",
      Subject: "Welcome",
      HtmlBody: "<strong>Hello</strong>",
    };

    await new ServerClient("service-secret").sendEmail(message);

    expect(fetchMock).toHaveBeenCalledOnce();
    const [url, request] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("http://api.test/internal/mail/outbound");
    expect(request.method).toBe("POST");
    expect(request.body).toBe(JSON.stringify(message));
    const headers = request.headers as Record<string, string>;
    const timestamp = headers["x-tapped-timestamp"];
    const expected = createHmac("sha256", "service-secret")
      .update(timestamp)
      .update(".")
      .update("")
      .update(".")
      .update(JSON.stringify(message))
      .digest("hex");
    expect(headers["x-tapped-signature"]).toBe(expected);
  });

  it("surfaces API failures to the Firebase trigger", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("unavailable", { status: 503 })));
    await expect(
      new ServerClient("service-secret").sendEmail({
        From: "no-reply@tapped.ai",
        To: "fan@example.com",
        Subject: "Welcome",
      }),
    ).rejects.toThrow("Tapped mail API returned 503");
  });
});

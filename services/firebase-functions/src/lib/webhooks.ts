import { error } from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { proxyToRust } from "./api_proxy";
import { MAIL_INGRESS_SECRET } from "./firebase";

// Keep the provider URL stable, but let Rust validate the original Stream signature
// and perform all persistence. Forward raw bytes: re-encoding JSON breaks HMAC.
export const streamBeforeMessageWebhook = onRequest({}, async (req, res) => {
  const signature = req.headers["x-signature"];
  if (typeof signature !== "string" || !signature) {
    res.status(400).send("no signature");
    return;
  }
  try {
    const response = await proxyToRust("/webhooks/stream/before-message", new Uint8Array(req.rawBody), {
      "x-signature": signature,
    });
    res.status(response.status).type(response.contentType).send(response.body);
  } catch (cause) {
    error("Failed to proxy Stream webhook", cause);
    res.status(502).send("API unavailable");
  }
});

// The existing Postmark plan cannot update its inbound webhook URL.
export const inboundEmailWebhook = onRequest({ secrets: [MAIL_INGRESS_SECRET] }, async (req, res) => {
  try {
    const authorization = Buffer.from(`postmark:${MAIL_INGRESS_SECRET.value()}`).toString("base64");
    const response = await proxyToRust("/webhooks/postmark/inbound", new Uint8Array(req.rawBody), {
      authorization: `Basic ${authorization}`,
    });
    res.status(response.status).type(response.contentType).send(response.body);
  } catch (cause) {
    error("Failed to proxy Postmark inbound email", cause);
    res.status(502).send("mail API unavailable");
  }
});

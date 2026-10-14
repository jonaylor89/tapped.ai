// Transport-only Firebase Auth hooks. Rust owns every lifecycle business effect.
import { createHmac } from "node:crypto";
import type { UserRecord } from "firebase-admin/auth";
import * as functions from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { proxyToRust } from "./api_proxy";

const AUTH_WEBHOOK_SECRET = defineSecret("AUTH_WEBHOOK_SECRET");

export async function forwardAuthEvent(kind: "signup" | "delete", user: UserRecord): Promise<void> {
  const createdAt = Date.parse(user.metadata.creationTime);
  if (!Number.isSafeInteger(createdAt) || createdAt <= 0) {
    throw new Error("Auth account creation time unavailable");
  }
  const secret = AUTH_WEBHOOK_SECRET.value();
  if (secret.length < 32) throw new Error("Auth webhook credential not configured");
  const body = Buffer.from(
    JSON.stringify({
      kind,
      account: {
        localId: user.uid,
        email: user.email ?? "",
        displayName: user.displayName ?? "",
        createdAt: String(createdAt),
      },
    }),
  );
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac("sha256", secret).update(`${timestamp}.`).update(body).digest("hex");
  const response = await proxyToRust("/webhooks/firebase/auth", body, {
    "x-tapped-timestamp": timestamp,
    "x-tapped-signature": signature,
  });
  // Throw on failure so Firebase retries; never acknowledge a lost lifecycle event.
  // Do not include the response/body/credential in logs or exception text.
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Auth lifecycle API HTTP ${response.status}`);
  }
}

const hooks = functions.runWith({ secrets: [AUTH_WEBHOOK_SECRET], failurePolicy: true }).auth.user();
// One transport per lifecycle event. Rust deduplicates retries and worker reconciliation.
export const onUserCreate = hooks.onCreate((user) => forwardAuthEvent("signup", user));
export const onUserDelete = hooks.onDelete((user) => forwardAuthEvent("delete", user));

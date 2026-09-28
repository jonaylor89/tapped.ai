/* eslint-disable import/no-unresolved */

import { error, info } from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { type Message, StreamChat, type User } from "stream-chat";
import type { UserModel } from "../types/models";
import { addUserToPremiumChat, removeUserFromPremiumChat } from "./direct_messaging";
import { sendEmailToVenueFromStreamMessage } from "./dm_email_sync/venue_contacting";
import {
  sendEmailSubscriptionExpiration,
  sendEmailSubscriptionPurchase,
  sendEmailToPerformerFromStreamMessage,
} from "./email_triggers";
import { MAIL_API_SECRET, MAIL_INGRESS_SECRET, streamKey, streamSecret, usersRef } from "./firebase";

// send email on subscription purchase
export const sendEmailOnSubscriptionPurchase = onRequest(
  { secrets: [MAIL_API_SECRET, streamKey, streamSecret] },
  async (req, res) => {
    try {
      info("sendEmailOnSubscriptionPurchase", req.body);
      const { event } = req.body;
      const { app_user_id: userId } = event;

      await sendEmailSubscriptionPurchase(MAIL_API_SECRET.value(), userId);

      // add them to group chat
      await addUserToPremiumChat(userId, {
        streamKey: streamKey.value(),
        streamSecret: streamSecret.value(),
      });

      res.sendStatus(200);
    } catch (e: any) {
      error(e.message);
      res.status(500);
    }
  },
);

export const sendEmailOnSubscriptionExpiration = onRequest(
  { secrets: [MAIL_API_SECRET, streamKey, streamSecret] },
  async (req, res) => {
    try {
      info("sendEmailOnSubscriptionExpiration", req.body);
      const { event } = req.body;
      const { app_user_id: userId } = event;

      await sendEmailSubscriptionExpiration(MAIL_API_SECRET.value(), userId);

      // remove from group chat
      await removeUserFromPremiumChat(userId, {
        streamKey: streamKey.value(),
        streamSecret: streamSecret.value(),
      });
    } catch (e: any) {
      error(e.message);
      res.status(500);
    }
  },
);

// Deprecated: configure Stream to call api.tapped.ai instead. Kept during rollout for rollback safety.
export const streamBeforeMessageWebhook = onRequest(
  { secrets: [streamKey, streamSecret, MAIL_API_SECRET] },
  async (req, res) => {
    const client = new StreamChat(streamKey.value(), streamSecret.value());

    const sig = req.headers["x-signature"];
    if (!sig || typeof sig !== "string") {
      res.status(400).send("no signature");
      return;
    }

    const valid = client.verifyWebhook(req.rawBody.toString(), sig);
    if (!valid) {
      res.status(403).send("invalid signature");
      return;
    }

    const json = req.body as {
      user: User | undefined;
      message: Message | undefined;
      members:
        | {
            user_id: string;
            user: User;
          }[]
        | undefined;
    };
    info({ json });

    // get sender
    const senderUser: User | undefined = json.user;
    // debug({ senderUser });

    // get receiver
    const receiverUser: User | undefined = json.members?.find(
      (m: { user: User }) => m.user.username !== senderUser?.username,
    )?.user;
    // debug({ receiverUser });

    // get message
    const msg = json.message?.text;
    // debug({ msg });
    const attachments = json.message?.attachments;

    const imagesAttachments =
      attachments?.filter((a) => a.type === "image" && a.image_url).map((a) => a.image_url as string) ?? [];

    if (!senderUser || !receiverUser || !msg) {
      res.status(400).send("bad request");
      return;
    }

    const receiverSnap = await usersRef.doc(receiverUser.id).get();
    if (!receiverSnap.exists) {
      throw new Error("no receiver found");
    }

    const receiverData = receiverSnap.data() as UserModel;
    // check if user is unclaimed
    if (!receiverData.unclaimed) {
      // send email to user if they have it in their settings
      await sendEmailToPerformerFromStreamMessage({
        msg,
        receiverData,
        senderUser,
        postmarkServerId: MAIL_API_SECRET.value(),
      });
    } else {
      // send email if venue
      await sendEmailToVenueFromStreamMessage({
        msg,
        attachments: imagesAttachments,
        receiverData,
        sender: senderUser,
        receiver: receiverUser,
        postmarkServerId: MAIL_API_SECRET.value(),
      });
    }
    res.status(200).send("ok");
  },
);

// Transitional proxy: the current Postmark plan cannot update its existing inbound webhook URL.
// Keep this function URL stable while all parsing, persistence, and Stream side effects run in Rust.
export const inboundEmailWebhook = onRequest({ secrets: [MAIL_INGRESS_SECRET] }, async (req, res) => {
  try {
    const apiUrl = process.env.TAPPED_API_URL ?? "https://api.tapped.ai";
    const authorization = Buffer.from(`postmark:${MAIL_INGRESS_SECRET.value()}`).toString("base64");
    const response = await fetch(`${apiUrl}/webhooks/postmark/inbound`, {
      method: "POST",
      headers: {
        authorization: `Basic ${authorization}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(req.body),
    });
    const responseBody = await response.text();
    res.status(response.status).send(responseBody);
  } catch (cause) {
    error("Failed to proxy Postmark inbound email", cause);
    res.status(502).send("mail API unavailable");
  }
});

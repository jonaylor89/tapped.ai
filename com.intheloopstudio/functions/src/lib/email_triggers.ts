/* eslint-disable import/no-unresolved */
import type { UserRecord } from "firebase-admin/auth";
import { Timestamp } from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import { debug, error, info } from "firebase-functions/logger";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { marked } from "marked";
import * as postmark from "postmark";
import type { User } from "stream-chat";
import Stripe from "stripe";
import { labelApplied } from "../email_templates/label_applied";
import { newDirectMessage } from "../email_templates/new_dm";
import { premiumWaitlist } from "../email_templates/premium_waitlist";
import { subscriptionExpiration } from "../email_templates/subscription_expiration";
import { subscriptionPurchase } from "../email_templates/subscription_purchase";
import { venueContacted } from "../email_templates/venue_contacted";
import { welcomeTemplate } from "../email_templates/welcome";
import type { Booking, MarketingPlan, UserModel } from "../types/models";
import {
  guestMarketingPlansRef,
  mailRef,
  POSTMARK_SERVER_ID,
  queuedWritesRef,
  stripeTestEndpointSecret,
  stripeTestKey,
  usersRef,
} from "./firebase";
// import { venueContacted } from "../email_templates/venue_contacted";

export const sendWelcomeEmailOnUserCreated = functions
  .runWith({ secrets: [POSTMARK_SERVER_ID] })
  .auth.user()
  .onCreate(async (user: UserRecord) => {
    const email = user.email;

    if (email === undefined || email === null || email === "") {
      throw new Error(`user email is undefined, null or empty: ${JSON.stringify(user)}`);
    }

    if (email.endsWith("@tapped.ai")) {
      debug(`user email ends with @tapped.ai, skipping welcome email: ${email}`);
      return;
    }

    debug(`sending welcome email to ${email}`);
    const client = new postmark.ServerClient(POSTMARK_SERVER_ID.value());
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: email,
      Subject: "welcome to tapped!",
      HtmlBody: `<div style="white-space: pre;">${welcomeTemplate}</div>`,
      MessageStream: "outbound",
    });
  });

export const sendEmailOnLabelApplication = onDocumentCreated(
  {
    document: "label_applications/{applicationId}",
    secrets: [POSTMARK_SERVER_ID],
  },
  async (event) => {
    const snapshot = event.data;
    const application = snapshot?.data();
    const email = application?.email;
    if (email === undefined || email === null || email === "") {
      throw new Error(`application ${application?.id} does not have an email`);
    }

    const client = new postmark.ServerClient(POSTMARK_SERVER_ID.value());
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: email,
      Subject: "thank you for applying to Tapped Ai!",
      HtmlBody: `<div style="white-space: pre;">${labelApplied}</div>`,
      MessageStream: "outbound",
    });
  },
);

export const emailMarketingPlanStripeWebhook = onRequest(
  { secrets: [stripeTestKey, stripeTestEndpointSecret, POSTMARK_SERVER_ID] },
  async (req, res) => {
    const stripe = new Stripe(stripeTestKey.value(), {
      apiVersion: "2022-11-15",
    });

    const client = new postmark.ServerClient(POSTMARK_SERVER_ID.value());
    const productIds = [
      "prod_Ojv2uMqEt5n60E", // test AI plan product
      "prod_OjsPZixnuZ86el", // prod AI plan product
    ];

    info("marketingPlanStripeWebhook", req.body);
    const sig = req.headers["stripe-signature"];
    if (!sig) {
      res.status(400).send("No signature");
      return;
    }

    try {
      const event = stripe.webhooks.constructEvent(req.rawBody, sig, stripeTestEndpointSecret.value());

      // Handle the event
      switch (event.type) {
        case "checkout.session.completed": {
          // eslint-disable-next-line no-case-declarations
          const checkoutSessionCompleted = event.data.object as unknown as {
            id: string;
            customer_email: string | null;
            customer_details: {
              email: string;
            };
          };

          // create firestore document for marketing plan set to 'processing' keyed at session_id
          info({ checkoutSessionCompleted });
          info({ sessionId: checkoutSessionCompleted.id });

          // get form data from firestore
          // eslint-disable-next-line no-case-declarations
          const checkoutSession = await stripe.checkout.sessions.retrieve(checkoutSessionCompleted.id, {
            expand: ["line_items"],
          });
          info({ checkoutSession });
          info({ lineItems: checkoutSession.line_items });
          // eslint-disable-next-line no-case-declarations
          const products = checkoutSession.line_items?.data?.map((item) => item.price?.product);
          // eslint-disable-next-line no-case-declarations
          const filteredArray = products?.filter((value) => productIds.includes(value?.toString() ?? "")) ?? [];
          if (filteredArray.length === 0) {
            debug(`incorrect product: ${products}`);
            return;
          }

          // eslint-disable-next-line no-case-declarations
          const { client_reference_id: clientReferenceId } = checkoutSession;
          if (clientReferenceId === null) {
            debug(`no client reference id: ${clientReferenceId}`);
            res.sendStatus(200);
            return;
          }
          info({ clientReferenceId });

          // save marketing plan to firestore and update status to 'complete'
          await guestMarketingPlansRef.doc(clientReferenceId).update({
            checkoutSessionId: checkoutSessionCompleted.id,
          });

          // eslint-disable-next-line no-case-declarations
          const marketingPlanRef = await guestMarketingPlansRef.doc(clientReferenceId).get();
          // eslint-disable-next-line no-case-declarations
          const marketingPlan = marketingPlanRef.data() as MarketingPlan;

          // email marketing plan to user
          // eslint-disable-next-line no-case-declarations
          const customerEmail =
            checkoutSessionCompleted.customer_email ?? checkoutSessionCompleted.customer_details.email;
          if (customerEmail !== null) {
            await client.sendEmail({
              From: "no-reply@tapped.ai",
              To: checkoutSessionCompleted.customer_email ?? checkoutSessionCompleted.customer_details.email,
              Subject: "Your Marketing Plan | Tapped Ai",
              HtmlBody: `<div>${marked.parse(marketingPlan.content)}</div>`,
              MessageStream: "outbound",
            });
          }

          break;
        }
        // ... handle other event types
        default:
          console.log(`Unhandled event type ${event.type}`);
      }

      // Return a 200 response to acknowledge receipt of the event
      res.sendStatus(200);
    } catch (err: any) {
      error(err);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }
  },
);

export const sendBookingRequestSentEmailOnBooking = functions.firestore
  .document("bookings/{bookingId}")
  .onCreate(async (data) => {
    const booking = data.data() as Booking;
    const requesterId = booking.requesterId;
    if (requesterId === null) {
      info("requesterId is null, skipping email");
      return;
    }

    const requesterSnapshot = await usersRef.doc(requesterId).get();
    const requester = requesterSnapshot.data();
    const requesterEmail = requester?.email;
    const unclaimed = requester?.unclaimed ?? false;
    const addedByUser = booking.addedByUser ?? false;
    const status = booking.status;

    debug({ requesterEmail, unclaimed, addedByUser });

    if (requesterEmail === undefined || requesterEmail === null || requesterEmail === "") {
      throw new Error(`requester ${requester?.id} does not have an email`);
    }

    if (unclaimed === true) {
      debug(`requester ${requester?.id} is unclaimed, skipping email`);
      return;
    }

    if (addedByUser === true) {
      debug(`requester ${requester?.id} was added by user, skipping email`);
      return;
    }

    if (requesterEmail.endsWith("@tapped.ai")) {
      debug(`requester ${requester?.id} email ends with @tapped.ai, skipping email`);
      return;
    }

    if (booking.calendarEventId !== undefined) {
      debug(`booking ${booking.id} already has a calendar event, skipping email`);
      return;
    }

    if (status !== "pending") {
      debug(`booking ${booking.id} is not pending, skipping email`);
      return;
    }

    await mailRef.add({
      to: [requesterEmail],
      template: {
        name: "bookingRequestSent",
      },
    });
  });

export const sendBookingRequestReceivedEmailOnBooking = functions.firestore
  .document("bookings/{bookingId}")
  .onCreate(async (data) => {
    const booking = data.data() as Booking;
    const requesteeSnapshot = await usersRef.doc(booking.requesteeId).get();
    const requestee = requesteeSnapshot.data();
    const requesteeEmail = requestee?.email;
    const unclaimed = requestee?.unclaimed ?? false;
    const addedByUser = requestee?.addedByUser ?? false;
    const status = booking.status;

    debug({ requesteeEmail, unclaimed, addedByUser });

    if (requesteeEmail === undefined || requesteeEmail === null || requesteeEmail === "") {
      throw new Error(`requestee ${requestee?.id} does not have an email`);
    }

    if (requesteeEmail.endsWith("@tapped.ai")) {
      debug(`requestee ${requestee?.id} email ends with @tapped.ai, skipping email`);
      return;
    }

    if (unclaimed === true) {
      debug(`requestee ${requestee?.id} is unclaimed, skipping email`);
      return;
    }

    if (addedByUser === true) {
      debug(`requestee ${requestee?.id} was added by user, skipping email`);
      return;
    }

    if (booking.calendarEventId !== undefined) {
      debug(`booking ${booking.id} already has a calendar event, skipping email`);
      return;
    }

    if (status !== "pending") {
      debug(`booking ${booking.id} is not pending, skipping email`);
      return;
    }

    await mailRef.add({
      to: [requesteeEmail],
      template: {
        name: "bookingRequestReceived",
      },
    });
  });

export const sendBookingNotificationsOnBookingConfirmed = functions.firestore
  .document("bookings/{bookingId}")
  .onUpdate(async (data) => {
    const booking = data.after.data() as Booking;
    const bookingBefore = data.before.data() as Booking;

    if (booking.status !== "confirmed" || bookingBefore.status === "confirmed") {
      functions.logger.info(`booking ${booking.id} is not confirmed or was already confirmed`);
      return;
    }

    const requesteeSnapshot = await usersRef.doc(booking.requesteeId).get();
    const requestee = requesteeSnapshot.data();
    const requesteeEmail = requestee?.email;
    const requesteeUnclaimed = requestee?.unclaimed ?? false;

    if (requesteeEmail === undefined || requesteeEmail === null || requesteeEmail === "") {
      throw new Error(`requestee ${requestee?.id} does not have an email`);
    }

    if (requesteeUnclaimed === true) {
      functions.logger.info(`requestee ${requestee?.id} is unclaimed, skipping email`);
      return;
    }

    const requesterId = booking.requesterId;
    if (requesterId === null) {
      info("requesterId is null, skipping email");
      return;
    }

    const requesterSnapshot = await usersRef.doc(requesterId).get();
    const requester = requesterSnapshot.data();
    const requesterEmail = requester?.email;
    const requesterUnclaimed = requester?.unclaimed ?? false;

    if (requesterEmail === undefined || requesterEmail === null || requesterEmail === "") {
      throw new Error(`requester ${requester?.id} does not have an email`);
    }

    if (requesterUnclaimed === true) {
      functions.logger.info(`requester ${requester?.id} is unclaimed, skipping email`);
      return;
    }

    const ONE_HOUR_MS = 60 * 60 * 1000;
    const ONE_DAY_MS = 24 * ONE_HOUR_MS;
    const ONE_WEEK_MS = 7 * ONE_DAY_MS;
    const reminders = [
      {
        userId: booking.requesteeId,
        email: requesteeEmail,
        offset: ONE_HOUR_MS,
        type: "bookingReminderRequestee",
      },
      {
        userId: booking.requesteeId,
        email: requesteeEmail,
        offset: ONE_DAY_MS,
        type: "bookingReminderRequestee",
      },
      {
        userId: booking.requesteeId,
        email: requesteeEmail,
        offset: ONE_WEEK_MS,
        type: "bookingReminderRequestee",
      },
      {
        userId: booking.requesterId,
        email: requesterEmail,
        offset: ONE_HOUR_MS,
        type: "bookingReminderRequester",
      },
      {
        userId: booking.requesterId,
        email: requesterEmail,
        offset: ONE_DAY_MS,
        type: "bookingReminderRequester",
      },
      {
        userId: booking.requesterId,
        email: requesterEmail,
        offset: ONE_WEEK_MS,
        type: "bookingReminderRequester",
      },
    ];

    const startTime = booking.startTime.toDate().getTime();

    // Create schedule write for push notification
    // 1 week, 1 day, and 1 hour before booking start time
    for (const reminder of reminders) {
      if (startTime - reminder.offset < Date.now()) {
        functions.logger.info("too late to send reminder, skipping reminder");
        continue;
      }

      await Promise.all([
        queuedWritesRef.add({
          state: "PENDING",
          data: {
            toUserId: reminder.userId,
            type: "bookingReminder",
            bookingId: booking.id,
            timestamp: Timestamp.now(),
            markedRead: false,
          },
          collection: "activities",
          deliverTime: Timestamp.fromMillis(startTime - reminder.offset),
        }),
        // queuedWritesRef.add({
        //   state: "PENDING",
        //   data: {
        //     to: [ reminder.email ],
        //     template: {
        //       // e.g. bookingReminderRequestee-3600000
        //       name: `${reminder.type}-${reminder.offset}`,
        //     },
        //   },
        //   collection: "mail",
        //   deliverTime: Timestamp.fromMillis(
        //     startTime - reminder.offset,
        //   ),
        // }),
      ]);
    }
  });

export const sendEmailOnPremiumWaitlist = onDocumentCreated(
  {
    document: "premiumWaitlist/{userId}",
    secrets: [POSTMARK_SERVER_ID],
  },
  async (event) => {
    const snapshot = event.data;
    const document = snapshot?.data();

    if (document === undefined) {
      return;
    }

    const userSnap = await usersRef.doc(document.id).get();
    if (!userSnap.exists) {
      error(`user does not exist ${document}`);
      return;
    }

    const user = userSnap.data() as UserModel;
    const email = user.email;

    if (email === undefined || email === null || email === "") {
      throw new Error(`${document?.id} does not have an email`);
    }

    const client = new postmark.ServerClient(POSTMARK_SERVER_ID.value());
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: email,
      Subject: "you're on the waitlist!",
      HtmlBody: `<div style="white-space: pre;">${premiumWaitlist}</div>`,
      MessageStream: "outbound",
    });
  },
);

export const _sendEmailOnVenueContacting = async ({
  userId,
  emailClient,
}: {
  userId: string;
  emailClient: postmark.ServerClient;
}): Promise<void> => {
  const userSnap = await usersRef.doc(userId).get();
  if (!userSnap.exists) {
    error(`user does not exist ${userId}`);
    return;
  }

  const user = userSnap.data() as UserModel;
  const email = user.email;

  if (email === undefined || email === null || email === "") {
    throw new Error(`${userId} does not have an email`);
  }

  await emailClient.sendEmail({
    From: "no-reply@tapped.ai",
    To: email,
    Subject: "performance request sent!",
    HtmlBody: `<div style="white-space: pre;">${venueContacted}</div>`,
    MessageStream: "outbound",
  });
};

export const sendEmailOnVenueContacting = onCall({ secrets: [POSTMARK_SERVER_ID] }, async (req) => {
  const { userId } = req.data;
  const emailClient = new postmark.ServerClient(POSTMARK_SERVER_ID.value());

  await _sendEmailOnVenueContacting({
    userId,
    emailClient,
  });
});

export async function sendEmailSubscriptionPurchase(postmarkServerId: string, userId: string): Promise<void> {
  const client = new postmark.ServerClient(postmarkServerId);

  const userSnap = await usersRef.doc(userId).get();
  if (!userSnap.exists) {
    error(`user does not exist ${userId}`);
    throw new Error(`user does not exist ${userId}`);
  }

  const user = userSnap.data() as UserModel;
  const email = user.email;

  if (email === undefined || email === null || email === "") {
    throw new Error(`email is undefined, null or empty: ${email}`);
  }

  await client.sendEmail({
    From: "no-reply@tapped.ai",
    To: email,
    Subject: "thank you for subscribing!",
    HtmlBody: `<div style="white-space: pre;">${subscriptionPurchase}</div>`,
    MessageStream: "outbound",
  });
}

export async function sendEmailSubscriptionExpiration(postmarkServerId: string, userId: string): Promise<void> {
  const client = new postmark.ServerClient(postmarkServerId);
  const userSnap = await usersRef.doc(userId).get();
  if (!userSnap.exists) {
    throw new Error(`user does not exist ${userId}`);
  }

  const user = userSnap.data() as UserModel;
  const email = user.email;

  if (email === undefined || email === null || email === "") {
    throw new Error(`email is undefined, null or empty: ${email}`);
  }

  await client.sendEmail({
    From: "no-reply@tapped.ai",
    To: email,
    Subject: "your subscription has expired!",
    HtmlBody: `<div style="white-space: pre;">${subscriptionExpiration}</div>`,
    MessageStream: "outbound",
  });
}

export async function sendEmailToPerformerFromStreamMessage({
  msg,
  receiverData,
  senderUser,
  postmarkServerId,
}: {
  msg: string;
  receiverData: UserModel;
  senderUser: User;
  postmarkServerId: string;
}): Promise<void> {
  const client = new postmark.ServerClient(postmarkServerId);
  const email = receiverData.email;

  if (email === undefined || email === null || email === "") {
    throw new Error(`email is undefined, null or empty: ${email}`);
  }

  if (receiverData.emailNotifications.directMessages === false) {
    return;
  }

  const html = newDirectMessage({
    msg,
    senderDisplayName: senderUser.name ?? senderUser.username ?? "someone",
  });

  await client.sendEmail({
    From: "no-reply@tapped.ai",
    To: email,
    Subject: `new message from ${senderUser.name}`,
    HtmlBody: `<div style="white-space: pre;">${html}</div>`,
    TextBody: msg,
    MessageStream: "outbound",
  });
}

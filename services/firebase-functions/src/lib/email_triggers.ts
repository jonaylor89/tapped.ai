/* eslint-disable import/no-unresolved */
import type { UserRecord } from "firebase-admin/auth";
import { Timestamp } from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import { debug, error, info } from "firebase-functions/logger";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

import type { User } from "stream-chat";

import { newDirectMessage } from "../email_templates/new_dm";
import { premiumWaitlist } from "../email_templates/premium_waitlist";
import { welcomeTemplate } from "../email_templates/welcome";
import type { Booking, UserModel } from "../types/models";
import { MAIL_API_SECRET, mailRef, queuedWritesRef, usersRef } from "./firebase";
import * as postmark from "./mail_client";
//
export const sendWelcomeEmailOnUserCreated = functions
  .runWith({ secrets: [MAIL_API_SECRET] })
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
    const client = new postmark.ServerClient(MAIL_API_SECRET.value());
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: email,
      Subject: "welcome to tapped!",
      HtmlBody: `<div style="white-space: pre;">${welcomeTemplate}</div>`,
      MessageStream: "outbound",
    });
  });

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
    secrets: [MAIL_API_SECRET],
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

    const client = new postmark.ServerClient(MAIL_API_SECRET.value());
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: email,
      Subject: "you're on the waitlist!",
      HtmlBody: `<div style="white-space: pre;">${premiumWaitlist}</div>`,
      MessageStream: "outbound",
    });
  },
);

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

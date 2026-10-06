/* eslint-disable import/no-unresolved */

import type { messaging } from "firebase-admin";
import * as functions from "firebase-functions";
import { debug } from "firebase-functions/logger";
import { fcm, tokensRef, usersRef } from "./firebase";

export const sendToDevice = functions.firestore.document("activities/{activityId}").onCreate(async (snapshot) => {
  const activity = snapshot.data();

  const userDoc = await usersRef.doc(activity.toUserId).get();
  const user = userDoc.data();
  if (user === null || user === undefined) {
    throw new Error("User not found");
  }

  if (user.email?.endsWith("@tapped.ai")) {
    debug("Skipping notification for tapped.ai user");
    return;
  }

  const activityType = activity.type;

  let payload: messaging.MessagingPayload = {
    notification: {
      title: "New Activity",
      body: "You have new activity on your profile",
      clickAction: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  switch (activityType) {
    case "bookingRequest":
      payload = {
        notification: {
          title: "New Booking Request",
          body: "You just got a new booking request 🔥",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      };
      break;
    case "bookingUpdate":
      payload = {
        notification: {
          title: "Booking Update",
          body: "There was an update to one of your bookings",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      };
      break;
    case "bookingReminder":
      payload = {
        notification: {
          title: "Booking Reminder",
          body: "You have a booking coming up soon!!!",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      };
      break;
    case "searchAppearance":
      payload = {
        notification: {
          title: "You're on the map!",
          body: "you've showed up in new searches this week 👀",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      };
      break;
    default:
      return;
  }

  const querySnapshot = await tokensRef.doc(activity.toUserId).collection("tokens").get();

  const tokens: string[] = querySnapshot.docs.map((snap) => snap.id);
  if (tokens.length === 0) {
    functions.logger.debug("No tokens to send to");
  }

  try {
    const resp = await fcm.sendToDevice(tokens, payload);
    if (resp.failureCount > 0) {
      functions.logger.warn(`Failed to send message to some devices: ${resp.failureCount}`);
    }
  } catch (e: any) {
    functions.logger.error(`${user.id} : ${e}`);
    throw new Error(`cannot send notification to device, userId: ${user.id}, ${e.message}`);
  }
});

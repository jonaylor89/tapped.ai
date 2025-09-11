/* eslint-disable import/no-unresolved */
import { onSchedule } from "firebase-functions/v2/scheduler";
import { HttpsError } from "firebase-functions/v2/https";
import * as functions from "firebase-functions";
import {
  bookingsRef,
  // servicesRef,
  usersRef,
  bookerReviewsSubcollection,
  performerReviewsSubcollection,
  SLACK_WEBHOOK_URL,
} from "./firebase";
import { Booking } from "../types/models";
// import { createActivity } from "./activities";
import { FieldValue } from "firebase-admin/firestore";
import { debug } from "firebase-functions/logger";
import { slackNotification } from "./notifications";
import { isNullOrUndefined } from "./utils";

const _updatePerformerRating = async ({
  userId,
  currRating,
  reviewCount,
  newRating,
}: {
  userId: string;
  currRating: number;
  reviewCount: number;
  newRating: number;
}) => {
  const overallRating =
    (currRating * reviewCount + newRating) / (reviewCount + 1);

  await usersRef.doc(userId).set(
    {
      performerInfo: {
        rating: overallRating,
      },
    },
    { merge: true },
  );
};

const _updateBookerRating = async ({
  userId,
  currRating,
  reviewCount,
  newRating,
}: {
  userId: string;
  currRating: number;
  reviewCount: number;
  newRating: number;
}) => {
  const overallRating =
    (currRating * reviewCount + newRating) / (reviewCount + 1);

  await usersRef.doc(userId).set(
    {
      bookerInfo: {
        rating: overallRating,
      },
    },
    { merge: true },
  );
};

// export const addActivityOnBooking = functions.firestore
//   .document("bookings/{bookingId}")
//   .onCreate(async (snapshot, context) => {
//     const booking = snapshot.data() as Booking;
//     if (booking === undefined) {
//       throw new HttpsError(
//         "failed-precondition",
//         `booking ${context.params.bookingId} does not exist`
//       );
//     }

//     const addedByUser = booking.addedByUser ?? false;
//     if (addedByUser === true) {
//       debug("booking added by user, not creating activity");
//       return;
//     }

//     createActivity({
//       fromUserId: booking.requesterId,
//       type: "bookingRequest",
//       toUserId: booking.requesteeId,
//       bookingId: context.params.bookingId,
//     });
//   });

// export const addActivityOnBookingUpdate = functions.firestore
//   .document("bookings/{bookingId}")
//   .onUpdate(async (change, context) => {
//     const booking = change.after.data() as Booking;
//     if (booking === undefined) {
//       throw new HttpsError(
//         "failed-precondition",
//         `booking ${context.params.bookingId} does not exist`
//       );
//     }

//     const status = booking.status as BookingStatus;

//     const uid = context.auth?.uid;

//     if (uid === undefined || uid === null) {
//       throw new HttpsError("unauthenticated", "user is not authenticated");
//     }

//     for (const userId of [ booking.requesterId, booking.requesteeId ]) {
//       if (userId === uid) {
//         continue;
//       }
//       await createActivity({
//         fromUserId: uid,
//         type: "bookingUpdate",
//         toUserId: userId,
//         bookingId: context.params.bookingId,
//         status: status,
//       });
//     }
//   });

export const notifyFoundersOnBookings = functions
  .runWith({ secrets: [ SLACK_WEBHOOK_URL ] })
  .firestore.document("bookings/{bookingId}")
  .onCreate(async (data) => {
    const booking = data.data() as Booking;
    if (booking === undefined) {
      throw new HttpsError(
        "failed-precondition",
        `booking ${data.id} does not exist`,
      );
    }

    if (
      !isNullOrUndefined(booking.scraperInfo) ||
      !isNullOrUndefined(booking.crawlerInfo)
    ) {
      debug("booking added by scraper, not sending notification");
      return;
    }

    const addedByUser = booking.addedByUser ?? false;
    if (addedByUser) {
      debug("booking added by user, not sending notification");

      if (booking.requesterId === undefined || booking.requesterId === null) {
        const requesteeSnapshot = await usersRef.doc(booking.requesteeId).get();
        const requestee = requesteeSnapshot.data();

        await slackNotification({
          title: "booking without location",
          body: `booking https://app.tapped.ai/booking/${data.id} has no venue. added by ${requestee?.username ? "https://app.tapped.ai/u/" + requestee.username : "<UNKNOWN>"} and requested`,
          slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
        });

        return;
      }

      return;
    }

    if (booking.requesterId === null) {
      await slackNotification({
        title: "booking without requester",
        body: `booking ${data.id} has no requester`,
        slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
      });
      return;
    }

    const requesterSnapshot = await usersRef.doc(booking.requesterId).get();
    const requester = requesterSnapshot.data();

    const requesteeSnapshot = await usersRef.doc(booking.requesteeId).get();
    const requestee = requesteeSnapshot.data();

    const msg = {
      title: "NEW TAPPED BOOKING!!!",
      body: `${requester?.artistName ?? "<UNKNOWN>"} booked ${
        requestee?.artistName ?? "<UNKNOWN>"
      }`,
    };
    await slackNotification({
      ...msg,
      slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
    });
  });

export const cancelBookingIfExpired = onSchedule("0 * * * *", async (event) => {
  const pendingBookings = await bookingsRef
    .where("status", "==", "pending")
    .limit(200)
    .get();

  for (const booking of pendingBookings.docs) {
    const bookingData = booking.data() as Booking;
    const timestamp = bookingData.startTime.toMillis();
    const now = Date.now();

    const ONE_DAY_MS = 24 * 60 * 60 * 1000;
    if (now > timestamp + ONE_DAY_MS) {
      await booking.ref.update({
        status: "canceled",
      });
    }
  }
});

export const incrementReviewCountOnBookerReview = functions.firestore
  .document(`reviews/{userId}/${bookerReviewsSubcollection}/{reviewId}`)
  .onCreate(async (data, context) => {
    const userId = context.params.userId;
    const userRef = usersRef.doc(userId);

    await userRef.set(
      {
        bookerInfo: {
          reviewCount: FieldValue.increment(1),
        },
      },
      { merge: true },
    );

    const currRating = (await userRef.get()).data()?.bookingInfo?.rating || 0;
    const reviewCount = (await userRef.get()).data()?.bookingInfo?.rating || 0;
    const newRating = data.data()?.overallRating || 0;

    _updateBookerRating({
      userId,
      currRating,
      reviewCount,
      newRating,
    });
  });

export const incrementReviewCountOnPerformerReview = functions.firestore
  .document(`reviews/{userId}/${performerReviewsSubcollection}/{reviewId}`)
  .onCreate(async (data, context) => {
    const userId = context.params.userId;
    const userRef = usersRef.doc(userId);

    await userRef.set(
      {
        performerInfo: {
          reviewCount: FieldValue.increment(1),
        },
      },
      { merge: true },
    );

    const currRating = (await userRef.get()).data()?.performerInfo?.rating || 0;
    const reviewCount =
      (await userRef.get()).data()?.performInfo?.reviewCount || 0;
    const newRating = data.data()?.overallRating || 0;

    _updatePerformerRating({
      userId,
      currRating,
      reviewCount,
      newRating,
    });
  });

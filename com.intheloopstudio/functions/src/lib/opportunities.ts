/* eslint-disable import/no-unresolved */
import * as functions from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import {
  SLACK_WEBHOOK_URL,
  creditsRef,
  opportunitiesRef,
  opportunityFeedsRef,
  usersRef,
} from "./firebase";
import { Opportunity, OpportunityFeedItem, UserModel } from "../types/models";
import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { debug } from "firebase-functions/logger";
// import { onSchedule } from "firebase-functions/v2/scheduler";
import { slackNotification } from "./notifications";
// import { v4 as uuidv4 } from "uuid";
// import { llm } from "./openai";

const _addOpportunityToUserFeed = async (
  userId: string,
  opData: Opportunity,
) => {
  await opportunityFeedsRef
    .doc(userId)
    .collection("opportunities")
    .doc(opData.id)
    .set({
      ...opData,
    });

  return;
};

const _addInterestedUserToOpportunity = async (
  userId: string,
  opFeedItem: OpportunityFeedItem,
) => {
  await opportunitiesRef
    .doc(opFeedItem.id)
    .collection("interestedUsers")
    .doc(userId)
    .set({
      userComment: opFeedItem.userComment,
      timestamp: Timestamp.now(),
    });

  return;
};

// const _copyOpportunityToFeeds = async (opportunity: Opportunity) => {
//   const usersSnap = await usersRef.get();

//   await Promise.all(
//     usersSnap.docs.map(async (userDoc) => {
//       if (userDoc.id === opportunity.userId) {
//         return;
//       }

//       const email = userDoc.data().email;
//       if (email.includes("tapped.ai")) {
//         return;
//       }

//       await _addOpportunityToUserFeed(userDoc.id, opportunity);
//     }),
//   );
// };

// const _createRandomOpportunity = async ({ venues, openaiKey }: {
//   venues: UserModel[];
//   openaiKey: string;
// }) => {
//   const eventTypes: {
//     type: string;
//     paid: number; // the probability that this event is paid
//     prompt: string; // the prompt for this event
//   }[] = [
//     {
//       type: "gig",
//       paid: 0.75,
//       prompt: "a gig opportunity",
//     },
//     {
//       type: "openMic",
//       paid: 0,
//       prompt: "a open mic"
//     },
//     {
//       type: "albumRelease",
//       paid: 0.75,
//       prompt: "needing an opening musician for an album release party",
//     },
//     {
//       type: "themedNight",
//       paid: 0.3,
//       prompt: "needing a musicians for a themed nights",
//     },
//     {
//       type: "battleOfTheBands",
//       paid: 0.9,
//       prompt: "battle of the bands opportunity for local bands",
//     },
//     {
//       type: "songwriterShowcase",
//       paid: 0.2,
//       prompt: "songwriter showcases opportunity for local songwriters",
//     },
//     {
//       type: "jamSession",
//       paid: 0,
//       prompt: "jam sessions for local bands",
//     },
//     {
//       type: "charityConcert",
//       paid: 0,
//       prompt: "needing local musicians for a charity concert",
//     },
//     {
//       type: "onlineStream",
//       paid: 0.5,
//       prompt: "needing local musicians for an online streaming event",
//     },
//   ];

//   const uuid = uuidv4();
//   const randomVenue = venues[Math.floor(Math.random() * venues.length)];
//   const currentDate = new Date();
//   const plusOneMonth = new Date(currentDate.setMonth(currentDate.getMonth() + 1));
//   const plusThreeMonths = new Date(currentDate.setMonth(currentDate.getMonth() + 3));
//   const randomDate = _generateRandomDate(plusOneMonth, plusThreeMonths);
//   const oneHourAhead = new Date(randomDate.getTime() + 60 * 60 * 1000);
//   const eventType = eventTypes[Math.floor(Math.random() * eventTypes.length)];

//   const randomPrompt = (() => {
//     // 8% of the time it'll have a crazy good prompt
//     // if (Math.random() > 0.05) {
//     //     return crazyIliasIdeaPrompt;
//     // }

//     const thePrompt = `you're a promoter looking to post online about ${eventType.prompt}.
//         what would the title of the event be and what would the 2 sentence description be?
//         the venue is called ${randomVenue.artistName}.
//         format your response as a valid JSON object`;
//     return thePrompt;
//   })();

//   const { title, description } = await (async () => {
//     // you get 3 tries to do this correctly
//     for (let i = 0; i < 3; i++) {
//       try {
//         const res = await llm(randomPrompt, openaiKey, { temperature: 0.4 });
//         const { title, description } = JSON.parse(res);
//         return { title, description };
//       } catch (e) {
//         console.error(e);
//         continue;
//       }
//     }

//     throw new Error(`your prompt fkn sucks - ${randomPrompt}`);
//   })()

//   if (title === undefined || description === undefined) {
//     console.log(`your prompt fkn sucks - ${randomPrompt}`);
//     return;
//   }

//   const op: Opportunity = {
//     id: uuid,
//     userId: randomVenue.id,
//     title,
//     description,
//     placeId: randomVenue.placeId!,
//     geohash: randomVenue.geohash!,
//     lat: randomVenue.lat!,
//     lng: randomVenue.lng!,
//     timestamp: new Date(),
//     startTime: randomDate,
//     endTime: oneHourAhead,
//     isPaid: Math.random() < eventType.paid,
//     touched: null,
//   }

//   console.log({ op });

//   await opportunitiesRef.doc(uuid).set({
//     ...op,
//     aiGenerated: true,
//   });

//   await _copyOpportunityToFeeds(op);
// }

// const _createMockOpportunities = async ({ count, openaiKey }: {
//   count: number;
//   openaiKey: string;
// }) => {
//   const venueBlacklist: string[] = [
//     "8ObJtER8PDUYKmQ0w7Tze0P6SHa2", // The Camel
//     "FsQWuDwH5lZxEpd7TpwXi7fFKqj1", // Alley RVA
//     "8R4gqTCxxzaNt1Bt4nLjqUEn6jd2", // Get Tight
//     "QGSNkGPB2wbEchwdD8VxJkhaBFN2", // VACU Ampitheatre
//     "jyz81JbwQycJoBzTTs4N724Gffc2", // The National
//     "tloWCuKGHYScMCp3YamsHKVi3XU2", // Brown's Island
//     "9FKyhrndDreJtzXnJc3eh6dt0QB2", // Sine's
//   ];

//   const virginiaVenues = await Promise.all(
//     virginiaVenueIds.concat(
//       dcVenueIds,
//       novaVenueIds,
//       marylandVenueIds,
//       virginiaBeachVenueIds,
//     ).filter(
//       (venueId) => !venueBlacklist.includes(venueId),
//     ).map(async (venueId) => {
//       const venueSnap = await usersRef.doc(venueId).get();
//       const venue = venueSnap.data()!;
//       return venue as UserModel;
//     }),
//   );

//   // const crazyIliasIdeaPrompt = `you're a promoter looking to post online about ${eventType}.
//   // what would the title of the event be and what would the 2 sentence description be?
//   // the venue is called ${randomVenue.artistName}.
//   // format your response as a valid JSON object`

//   const opPromises: Promise<void>[] = [];
//   for (let i = 0; i < count; i++) {
//     opPromises.push(_createRandomOpportunity({ venues: virginiaVenues, openaiKey }));
//   }

//   await Promise.all(opPromises);
// };

// function _generateRandomDate(from: Date, to: Date) {
//   return new Date(
//     from.getTime() +
//     Math.random() * (to.getTime() - from.getTime()),
//   );
// }

// const _sendUserQuotaNotification = async (
//   userId: string,
//   openaiKey: string,
// ) => {

//   // add new opportunities to the feed
//   // try {
//   //   await _createMockOpportunities({ count: 10, openaiKey });
//   // } catch (e) {
//   //   error("error creating mock opportunities", e);
//   // }

//   // get userId device tokens
//   const tokensSnap = await tokensRef
//     .doc(userId)
//     .collection("tokens")
//     .get();

//   const tokens: string[] = tokensSnap.docs.map((snap) => snap.id);
//   await Promise.all(tokens.map(async (token) => {
//     try {

//       await fcm.send({
//         token,
//         notification: {
//           title: "you're back!",
//           body: "you can apply for 5 more opportunities today!",
//         },
//       });
//     } catch (e) {
//       error(`error sending quota notification to ${userId} - ${token}`, e);
//       await tokensRef.doc(userId).collection("tokens").doc(token).delete();
//     }
//   }));
// }

// const _setDailyOpportunityQuota = async () => {
//   const usersSnap = await usersRef
//     .where("deleted", "!=", true)
//     .where("unclaimed", "in", [ false, null ])
//     .get();

//   await Promise.all(
//     usersSnap.docs.map(async (userDoc): Promise<void> => {
//       try {
//         await creditsRef.doc(userDoc.id).set(
//           {
//             opportunityQuota: 5,
//           },
//           { merge: true },
//         );
//       } catch (e) {
//         error("error setting daily opportunity quota", e);
//       }
//     }),
//   );
//   info("daily opportunity quotas set");
// };

export const notifyFoundersOnOpportunityInterest = functions
  .runWith({ secrets: [ SLACK_WEBHOOK_URL ] })
  .firestore.document("opportunities/{opportunityId}/interestedUsers/{userId}")
  .onCreate(async (data, context) => {
    const { userComment } = data.data() as {
      userComment: string;
      timestamp: Timestamp;
    };

    const opSnap = await opportunitiesRef
      .doc(context.params.opportunityId)
      .get();
    const op = opSnap.data() as Opportunity;

    const userSnap = await usersRef.doc(context.params.userId).get();
    const user = userSnap.data() as UserModel;
    const displayName = user.artistName || user.username;

    await slackNotification({
      slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
      title: `${displayName} applied for "${op.title}"`,
      body: `https://app.tapped.ai/u/${user.username} applied for https://app.tapped.ai/opportunity/${op.id} with the comment  \n\n"${userComment}"`,
    });
  });

export const copyOpportunityToFeedsOnCreate = onDocumentWritten(
  { document: "opportunities/{opportunityId}" },
  async (event) => {
    const snapshot = event.data;
    const afterDoc = snapshot?.after;
    const opportunity = afterDoc?.data() as Opportunity | undefined;

    if (opportunity === undefined) {
      throw new HttpsError("failed-precondition", "opportunity does not exist");
    }

    const usersSnap = await usersRef.get();

    await Promise.all(
      usersSnap.docs.map(async (userDoc) => {
        if (userDoc.id === opportunity.userId) {
          return;
        }

        await _addOpportunityToUserFeed(userDoc.id, opportunity);
      }),
    );
  },
);

export const createOpportunityFeedOnUserCreated = functions.auth
  .user()
  .onCreate(async (user) => {
    const numOpsPerFeed = 500;
    const opportunitiesSnap = await opportunitiesRef
      .where("startTime", ">", Timestamp.now())
      .limit(numOpsPerFeed)
      .get();

    await creditsRef.doc(user.uid).set(
      {
        opportunityQuota: 5,
      },
      { merge: true },
    );

    await Promise.all(
      opportunitiesSnap.docs.map(async (opDoc) => {
        const op = opDoc.data() as Opportunity;
        await _addOpportunityToUserFeed(user.uid, op);
      }),
    );
  });

export const addInterestedUserOnApplyToOpportunity = onDocumentUpdated(
  { document: "opportunityFeeds/{userId}/opportunities/{opportunityId}" },
  async (event) => {
    const snapshot = event.data;
    const userId = event.params.userId;
    const beforeOpSnap = snapshot?.before;
    const afterOpSnap = snapshot?.after;

    const beforeOp = beforeOpSnap?.data() as Opportunity | undefined;
    const afterOp = afterOpSnap?.data() as Opportunity | undefined;

    if (beforeOp === undefined || afterOp === undefined) {
      throw new HttpsError(
        "failed-precondition",
        "before or after does not exist",
      );
    }

    if (beforeOp.touched !== undefined && beforeOp.touched !== null) {
      debug("beforeOp.touched is already set", { beforeOp });
      return;
    }

    if (afterOp.touched !== "like") {
      debug("afterOp.touched !== like", { afterOp });
      return;
    }

    await _addInterestedUserToOpportunity(userId, afterOp);
  },
);

export const copyOpportunitiesToFeedOnCreateUser = onDocumentCreated(
  { document: "users/{userId}" },
  async (event) => {
    const snapshot = event.data;
    const user = snapshot?.data() as UserModel | undefined;

    if (user === undefined) {
      throw new HttpsError("failed-precondition", "user does not exist");
    }

    const opportunitiesSnap = await opportunitiesRef
      .where("startTime", ">", Timestamp.now())
      .limit(25)
      .get();

    await Promise.all(
      opportunitiesSnap.docs.map(async (opDoc) => {
        const op = opDoc.data() as Opportunity;
        await _addOpportunityToUserFeed(user.id, op);
      }),
    );
  },
);

// export const setDailyOpportunityQuota = onSchedule(
//   "0 0 * * *",
//   _setDailyOpportunityQuota,
// );

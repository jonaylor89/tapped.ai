/* eslint-disable import/no-unresolved */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import * as functions from "firebase-functions";
import { error, info } from "firebase-functions/logger";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { marked } from "marked";
import * as postmark from "postmark";
import Stripe from "stripe";
import { v4 as uuidv4 } from "uuid";
import type { MarketingPlan, UserModel } from "../types/models";
import {
  creditsPerPriceId,
  creditsPerTestPriceId,
  creditsRef,
  guestMarketingPlansRef,
  marketingFormsRef,
  marketingPlansRef,
  OPEN_AI_KEY,
  POSTMARK_SERVER_ID,
  SLACK_WEBHOOK_URL,
  stripeCoverArtTestWebhookSecret,
  stripeCoverArtWebhookSecret,
  stripeKey,
  stripeTestEndpointSecret,
  stripeTestKey,
  usersRef,
} from "./firebase";
import { slackNotification } from "./notifications";
import { basicEnhancedBio, generateBasicMarketingPlan, generateSingleBasicMarketingPlan } from "./openai";
import { authenticatedRequest } from "./utils";

const _incrementCoverArtTestCredits = async (
  stripe: Stripe,
  checkoutSessionCompleted: {
    id: string;
    client_reference_id: string | null;
    customer_email: string | null;
    customer_details: {
      email: string;
    };
  },
) => {
  const userId = checkoutSessionCompleted.client_reference_id;

  if (userId === null) {
    throw new HttpsError("failed-precondition", "client reference id not set");
  }

  // create firestore document for marketing plan set to 'processing' keyed at session_id
  info({ checkoutSessionCompleted });
  info({ sessionId: checkoutSessionCompleted.id });

  // get form data from firestore
  const checkoutSession = await stripe.checkout.sessions.retrieve(checkoutSessionCompleted.id);
  info({ checkoutSession });

  // const customerEmail = checkoutSessionCompleted.customer_email ?? checkoutSessionCompleted.customer_details.email;

  const lineItems = await stripe.checkout.sessions.listLineItems(checkoutSessionCompleted.id);
  const quantity = lineItems.data[0].quantity;
  const priceId = lineItems.data[0].price?.id ?? "";
  const creditsPerUnit = creditsPerTestPriceId[priceId];
  const totalCreditsPurchased = quantity! * creditsPerUnit;

  console.log({ lineItems });
  console.log({ quantity });
  console.log({ priceId });
  console.log({ creditsPerUnit });

  console.log(`totalCreditsPurchased: ${totalCreditsPurchased}`);

  await creditsRef.doc(userId).update({
    coverArtCredits: FieldValue.increment(totalCreditsPurchased),
  });
};

const _incrementCoverArtCredits = async (
  stripe: Stripe,
  checkoutSessionCompleted: {
    id: string;
    client_reference_id: string | null;
    customer_email: string | null;
    customer_details: {
      email: string;
    };
  },
) => {
  const userId = checkoutSessionCompleted.client_reference_id;

  if (userId === null) {
    throw new HttpsError("failed-precondition", "client reference id not set");
  }

  // create firestore document for marketing plan set to 'processing' keyed at session_id
  info({ checkoutSessionCompleted });
  info({ sessionId: checkoutSessionCompleted.id });

  // get form data from firestore
  const checkoutSession = await stripe.checkout.sessions.retrieve(checkoutSessionCompleted.id);
  info({ checkoutSession });

  // const customerEmail = checkoutSessionCompleted.customer_email ?? checkoutSessionCompleted.customer_details.email;

  const lineItems = await stripe.checkout.sessions.listLineItems(checkoutSessionCompleted.id);
  const quantity = lineItems.data[0].quantity;
  const priceId = lineItems.data[0].price?.id ?? "";
  const creditsPerUnit = creditsPerPriceId[priceId];
  const totalCreditsPurchased = quantity! * creditsPerUnit;

  console.log({ lineItems });
  console.log({ quantity });
  console.log({ priceId });
  console.log({ creditsPerUnit });

  console.log(`totalCreditsPurchased: ${totalCreditsPurchased}`);

  await creditsRef.doc(userId).update({
    coverArtCredits: FieldValue.increment(totalCreditsPurchased),
  });
};

const _giveUserCoverArtCredits = async (userId: string, amount: number) => {
  await creditsRef.doc(userId).set(
    {
      coverArtCredits: FieldValue.increment(amount),
    },
    { merge: true },
  );
};

const _emailMarketingPlan = async ({
  checkoutSessionCompleteId,
  checkoutSession,
  customerEmail,
  postmarkServerId,
}: {
  checkoutSessionCompleteId: string;
  checkoutSession: Stripe.Response<Stripe.Checkout.Session>;
  customerEmail: string | null;
  postmarkServerId: string;
}) => {
  const client = new postmark.ServerClient(postmarkServerId);

  const { client_reference_id: clientReferenceId } = checkoutSession;
  if (clientReferenceId === null) {
    throw new Error("no client reference id");
  }
  info({ clientReferenceId });

  await guestMarketingPlansRef.doc(clientReferenceId).update({
    status: "processing",
  });

  const formDataRef = await marketingFormsRef.doc(clientReferenceId).get();

  const formData = formDataRef.data();
  if (!formData || !formDataRef.exists) {
    throw new Error("no form data");
  }

  info({ formData });

  // TODO: get use follower count
  // TODO: switch case for if it's a single, EP, or album
  const { content, prompt } = await generateBasicMarketingPlan({
    releaseType: formData.marketingType,
    artistName: formData.artistName,
    // artistGenres: formData.genre,
    // igFollowerCount,
    singleName: formData.productName,
    aesthetic: formData.aesthetic,
    targetAudience: formData.audience,
    moreToCome: formData.moreToCome ?? "nothing",
    releaseTimeline: formData.timeline,
    apiKey: OPEN_AI_KEY.value(),
  });

  // save marketing plan to firestore and update status to 'complete'
  await guestMarketingPlansRef.doc(clientReferenceId).update({
    status: "completed",
    checkoutSessionCompleteId,
    content,
    prompt,
  });

  // email marketing plan to user
  if (customerEmail !== null) {
    await client.sendEmail({
      From: "no-reply@tapped.ai",
      To: customerEmail,
      Subject: "Your Marketing Plan",
      HtmlBody: `<div>${marked.parse(content)}</div>`,
      TextBody: "Your Marketing Plan",
      MessageStream: "outbound",
    });
  }
};

export const createSingleMarketingPlan = onCall({ secrets: [OPEN_AI_KEY] }, async (request) => {
  const openAiKey = OPEN_AI_KEY.value();
  const { userId, name, aesthetic, targetAudience, moreToCome, releaseTimeline } = request.data;

  info({
    userId,
    name,
    aesthetic,
    targetAudience,
    moreToCome,
    releaseTimeline,
  });

  const userSnapshot = await usersRef.doc(userId).get();
  if (!userSnapshot.exists) {
    throw new HttpsError("failed-precondition", `user ${userId} does not exist`);
  }

  const artistName = userSnapshot.data()?.username;
  const artistGenres = userSnapshot.data()?.genres;

  // const labelApplicationsQuery = await labelApplicationsRef.where("id", "==", userId).get();
  // if (labelApplicationsQuery.empty) {
  //   throw new HttpsError("failed-precondition", `user ${userId} does not have a label application`);
  // }

  // const igFollowerCount = labelApplicationsQuery.docs[0].data().igFollowerCount;

  const { content, prompt } = await generateSingleBasicMarketingPlan({
    artistName,
    artistGenres,
    // igFollowerCount,
    singleName: name,
    aesthetic,
    targetAudience,
    moreToCome,
    releaseTimeline,
    apiKey: openAiKey,
  });

  const uuid = uuidv4();
  const marketingPlan: MarketingPlan = {
    id: uuid,
    userId: userId,
    name: name,
    type: "single",
    content: content,
    prompt: prompt,
    timestamp: Timestamp.now(),
  };
  await marketingPlansRef.doc(userId).collection("userMarketingPlans").doc(uuid).set(marketingPlan);

  return {
    content,
    prompt,
  };
});

export const marketingPlanStripeWebhook = onRequest(
  {
    secrets: [stripeTestKey, stripeTestEndpointSecret, POSTMARK_SERVER_ID, OPEN_AI_KEY],
  },
  async (req, res) => {
    const stripe = new Stripe(stripeTestKey.value(), {
      apiVersion: "2022-11-15",
    });

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
          const checkoutSession = await stripe.checkout.sessions.retrieve(checkoutSessionCompleted.id);
          info({ checkoutSession });

          // eslint-disable-next-line no-case-declarations
          const customerEmail =
            checkoutSessionCompleted.customer_email ?? checkoutSessionCompleted.customer_details.email;
          await _emailMarketingPlan({
            checkoutSessionCompleteId: checkoutSessionCompleted.id,
            checkoutSession,
            customerEmail,
            postmarkServerId: POSTMARK_SERVER_ID.value(),
          });
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

export const generateMarketingPlan = functions
  .runWith({
    secrets: [POSTMARK_SERVER_ID, OPEN_AI_KEY],
  })
  .firestore.document("marketingForms/{clientReferenceId}")
  .onCreate(async (_request, context) => {
    const clientReferenceId = context.params.clientReferenceId;
    if (clientReferenceId === null) {
      throw new HttpsError("invalid-argument", "no client reference id");
    }
    info({ clientReferenceId });

    await guestMarketingPlansRef.doc(clientReferenceId).update({
      status: "processing",
    });

    const formDataRef = await marketingFormsRef.doc(clientReferenceId).get();

    const formData = formDataRef.data();
    if (!formData || !formDataRef.exists) {
      throw new HttpsError("failed-precondition", "no form data");
    }

    info({ formData });

    // TODO: get use follower count
    const { content, prompt } = await generateBasicMarketingPlan({
      releaseType: formData.marketingType,
      artistName: formData.artistName,
      // artistGenres: formData.genre,
      // igFollowerCount,
      singleName: formData.productName,
      aesthetic: formData.aesthetic,
      targetAudience: formData.audience,
      moreToCome: formData.moreToCome ?? "nothing",
      releaseTimeline: formData.timeline,
      apiKey: OPEN_AI_KEY.value(),
    });

    // save marketing plan to firestore and update status to 'complete'
    await guestMarketingPlansRef.doc(clientReferenceId).update({
      status: "completed",
      // checkoutSessionId: checkoutSessionCompleted.id,
      content,
      prompt,
    });
  });

export const coverArtStripeTestWebhook = onRequest(
  {
    secrets: [stripeTestKey, stripeCoverArtTestWebhookSecret],
  },
  async (req, res) => {
    const stripe = new Stripe(stripeTestKey.value(), {
      apiVersion: "2022-11-15",
    });

    info("coverArtStripeTestWebhook", req.body);
    const sig = req.headers["stripe-signature"];
    if (!sig) {
      res.status(400).send("No signature");
      return;
    }

    try {
      const event = stripe.webhooks.constructEvent(req.rawBody, sig, stripeCoverArtTestWebhookSecret.value());

      // Handle the event
      switch (event.type) {
        case "checkout.session.completed": {
          // eslint-disable-next-line no-case-declarations
          const checkoutSessionCompleted = event.data.object as unknown as {
            id: string;
            client_reference_id: string | null;
            customer_email: string | null;
            customer_details: {
              email: string;
            };
          };

          await _incrementCoverArtTestCredits(stripe, checkoutSessionCompleted);
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

export const coverArtStripeWebhook = onRequest(
  {
    secrets: [stripeKey, stripeCoverArtWebhookSecret],
  },
  async (req, res) => {
    const stripe = new Stripe(stripeKey.value(), {
      apiVersion: "2022-11-15",
    });

    info("coverArtStripeWebhook", req.body);
    const sig = req.headers["stripe-signature"];
    if (!sig) {
      res.status(400).send("No signature");
      return;
    }

    try {
      const event = stripe.webhooks.constructEvent(req.rawBody, sig, stripeCoverArtWebhookSecret.value());

      // Handle the event
      switch (event.type) {
        case "checkout.session.completed": {
          // eslint-disable-next-line no-case-declarations
          const checkoutSessionCompleted = event.data.object as unknown as {
            id: string;
            client_reference_id: string | null;
            customer_email: string | null;
            customer_details: {
              email: string;
            };
          };
          await _incrementCoverArtCredits(stripe, checkoutSessionCompleted);
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

export const generateEnhancedBio = onCall({ secrets: [OPEN_AI_KEY] }, async (request) => {
  authenticatedRequest(request);
  // pull artist data
  const userId = request.auth?.uid;
  if (userId === undefined) {
    throw new HttpsError("unauthenticated", "user is not authenticated");
  }

  const userSnapshot = await usersRef.doc(userId).get();
  const userData = userSnapshot.data() as UserModel;

  const displayName = userData?.artistName ?? userData?.username ?? "";
  const twitterHandle = userData?.socialFollowing?.twitterHandle ?? "";
  const tiktokHandle = userData?.socialFollowing?.tiktokHandle ?? "";
  const instagramHandle = userData?.socialFollowing?.instagramHandle ?? "";
  const artistGenres = userData?.performerInfo?.genres ?? [];

  const openAiKey = OPEN_AI_KEY.value();
  const { content } = await basicEnhancedBio({
    apiKey: openAiKey,
    artistName: displayName,
    twitterHandle,
    tiktokHandle,
    instagramHandle,
    artistGenres,
  });

  return {
    enhancedBio: content,
  };
});

export const giveUserCoverArtCreditsOnCreate = functions.auth.user().onCreate(async (user) => {
  await _giveUserCoverArtCredits(user.uid, 15);
});

export const notifyFoundersOnMarketingForm = functions
  .runWith({ secrets: [SLACK_WEBHOOK_URL] })
  .firestore.document("marketingForm/{formId}")
  .onCreate(async (snapshot) => {
    const form = snapshot.data();
    await slackNotification({
      title: "New Marketing Form \uD83D\uDE43",
      body: `${form.artistName} just created a marketing plan`,
      slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
    });
  });

export const notifyFoundersOnGuestMarketingPlan = functions
  .runWith({ secrets: [SLACK_WEBHOOK_URL] })
  .firestore.document("guestMarketingPlans/{planId}")
  .onCreate(async () => {
    await slackNotification({
      title: "New Marketing Plan \uD83D\uDE43",
      body: "Someone just created a marketing plan",
      slackWebhookUrl: SLACK_WEBHOOK_URL.value(),
    });
  });

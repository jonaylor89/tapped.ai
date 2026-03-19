import type * as postmark from "postmark";
import type { Booking, Opportunity, UserModel } from "../../types/models";
import { bookingsRef, usersRef } from "../firebase";
import { chatGpt } from "../openai";

async function buildOpportunitySnippet(opportunities: Opportunity[]): Promise<string> {
  const shortenedOps = await Promise.all(
    opportunities.map(async (o) => {
      const referenceEventId = o.referenceEventId;
      if (!referenceEventId) {
        return {
          title: o.title,
          date: o.startTime.toDate().toISOString().split("T")[0],
          otherOpPerformers: [] as string[],
        };
      }

      const bookingsSnap = await bookingsRef.where("referenceEventId", "==", referenceEventId).get();

      const otherOpPerformers = await Promise.all(
        bookingsSnap.docs.map(async (doc) => {
          const booking = doc.data() as Booking;
          const requesteeDoc = await usersRef.doc(booking.requesteeId).get();
          const requestee = requesteeDoc.data() as UserModel;
          return requestee.artistName ?? requestee.username;
        }),
      );

      return {
        title: o.title,
        date: o.startTime.toDate().toISOString().split("T")[0],
        otherOpPerformers,
      };
    }),
  );

  return shortenedOps
    .map((o) => `${o.title} on ${o.date} with these other performers ${o.otherOpPerformers.join(",")}. `)
    .join("\n");
}

export async function composeVenueEmail({
  performer,
  venue,
  note,
  opportunities,
  previousEmails,
}: {
  performer: UserModel;
  venue: UserModel;
  note: string;
  opportunities: Opportunity[];
  previousEmails?: postmark.Message[];
}): Promise<{
  subject: string;
  body: string;
}> {
  const displayName = performer.artistName || performer.username;
  const genres = performer.performerInfo?.genres?.join(", ") ?? "";
  const venueName = venue.artistName;
  const subject = `Performance Inquiry from ${displayName}`;

  const emailThreadSection =
    previousEmails && previousEmails.length > 0
      ? `\n  Previous Conversations/Email Thread: \n  ###\n  ${previousEmails.map((e) => e.TextBody).join("\n--------------")}\n  ###\n`
      : "";

  const infoSection = `
  Venue Name: ${venueName}
  Performer Name: ${displayName}
  ${genres !== "" ? `Perfomers Genres: ${genres}` : ""}

  ${note !== "" ? `Note: ${note}` : ""}
${emailThreadSection}`;

  let prompt: string;
  if (opportunities.length > 0) {
    const opportunitySnippet = await buildOpportunitySnippet(opportunities);
    prompt = `${infoSection}
  --------------------------
  Given the information above, write an paragraph to send that you're open to performing with this:
  ${opportunitySnippet}
  

  The paragraph should be friendly, professional, and a little dry (i.e. straight to the point).
  Be sure to mention that you were recommended to reach out be Tapped Ai.
  Your response should ONLY use the information provider and assume that's all the information that's available.
  Don't include any intro like "dear venue owner" or signature like "sincerly" or "thanks".
  Be concise, to the point and keep it short.
      `;
  } else {
    prompt = `${infoSection}
  --------------------------
  Given the information above, write an paragraph to send to venues to request a booking in the style
  of a musicians looking to perform there.
  The paragraph should be friendly, professional, and a little dry (i.e. straight to the point).
  Be sure to mention that you were recommended to reach out be Tapped Ai.
  Your response should ONLY use the information provider and assume that's all the information that's available.
  Don't include any intro like "dear venue owner" or signature like "sincerly" or "thanks".
  Be concise, to the point and keep it short.
  `;
  }

  const body = await chatGpt(prompt);
  return { subject, body };
}

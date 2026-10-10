import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { GeoPoint, Timestamp, getFirestore } from "firebase-admin/firestore";
import { Pool } from "pg";
import { requireDatabaseUrl } from "./helpers/database";

const app = getApps()[0] ?? initializeApp({ credential: process.env.GOOGLE_APPLICATION_CREDENTIALS ? applicationDefault() : cert(require("./in-the-loop-306520-firebase-adminsdk-60hh4-b0eb65b2df.json")) });
const db = getFirestore(app);
const apply = process.argv.includes("--apply");

type Data = Record<string, unknown>;
const record = (value: unknown): value is Data => value !== null && typeof value === "object" && !Array.isArray(value);
const text = (value: unknown): string | null => typeof value === "string" && value ? value : null;
const time = (value: unknown): string | null => value instanceof Timestamp ? value.toDate().toISOString() : value instanceof Date ? value.toISOString() : null;
const json = (value: unknown): unknown => {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof GeoPoint) return { latitude: value.latitude, longitude: value.longitude };
  if (Array.isArray(value)) return value.map(json);
  if (record(value)) return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, json(v)]));
  return value;
};
function location(data: Data) {
  const value = record(data.location) ? data.location : {};
  const lat = value.lat ?? value.latitude;
  const lng = value.lng ?? value.longitude;
  const valid = typeof lat === "number" && lat >= -90 && lat <= 90 && typeof lng === "number" && lng >= -180 && lng <= 180;
  return { lat: valid ? lat : null, lng: valid ? lng : null, placeId: text(value.placeId) ?? text(data.placeId) };
}
function profile(data: Data, removed: string[]) { return Object.fromEntries(Object.entries(data).filter(([key]) => !removed.includes(key)).map(([key, value]) => [key, json(value)])); }
async function main() {
  const pool = apply ? new Pool({ connectionString: requireDatabaseUrl(), max: 1 }) : undefined;
  const counts = { opportunities: 0, interests: 0, reviews: 0, invalidLocations: 0 };
  try {
    const opportunities = await db.collection("opportunities").get();
    const client = pool ? await pool.connect() : undefined;
    try {
      if (client) await client.query("BEGIN");
      for (const doc of opportunities.docs) {
        const data = doc.data() as Data; const point = location(data); if (data.location && point.lat === null) counts.invalidLocations++;
        if (client) await client.query(`INSERT INTO opportunities (id,user_id,title,description,flier_url,location,place_id,occurred_at,start_time,end_time,deadline,genres,is_paid,venue_id,reference_event_id,deleted,profile,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,CASE WHEN $6::double precision IS NULL THEN NULL ELSE ST_SetSRID(ST_MakePoint($7::double precision,$6::double precision),4326)::geography END,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18::jsonb,$19,$20) ON CONFLICT (id) DO UPDATE SET user_id=EXCLUDED.user_id,title=EXCLUDED.title,description=EXCLUDED.description,flier_url=EXCLUDED.flier_url,location=EXCLUDED.location,place_id=EXCLUDED.place_id,occurred_at=EXCLUDED.occurred_at,start_time=EXCLUDED.start_time,end_time=EXCLUDED.end_time,deadline=EXCLUDED.deadline,genres=EXCLUDED.genres,is_paid=EXCLUDED.is_paid,venue_id=EXCLUDED.venue_id,reference_event_id=EXCLUDED.reference_event_id,deleted=EXCLUDED.deleted,profile=EXCLUDED.profile`, [doc.id,text(data.userId),text(data.title) ?? "",text(data.description) ?? "",text(data.flierUrl),point.lat,point.lng,point.placeId,time(data.timestamp),time(data.startTime),time(data.endTime),time(data.deadline),Array.isArray(data.genres) ? data.genres.filter((x): x is string => typeof x === "string") : [],data.isPaid === true,text(data.venueId),text(data.referenceEventId),data.deleted === true,JSON.stringify(profile(data,["id","userId","title","description","flierUrl","location","placeId","timestamp","startTime","endTime","deadline","genres","isPaid","venueId","referenceEventId","deleted"])),doc.createTime?.toDate(),doc.updateTime?.toDate()]);
        counts.opportunities++;
      }
      const interests = await db.collectionGroup("interestedUsers").get();
      for (const doc of interests.docs) { const opportunityId = doc.ref.parent.parent?.id; if (!opportunityId) continue; if (client) await client.query(`INSERT INTO opportunity_interested_users (opportunity_id,user_id,profile,created_at,updated_at) VALUES ($1,$2,$3::jsonb,$4,$5) ON CONFLICT (opportunity_id,user_id) DO UPDATE SET profile=EXCLUDED.profile`, [opportunityId,doc.id,JSON.stringify(json(doc.data())),doc.createTime?.toDate(),doc.updateTime?.toDate()]); counts.interests++; }
      // Explicit one-time repair before Postgres serves clients; never use after opening API writes.
      if (client && process.argv.includes("--replace-reviews")) await client.query("DELETE FROM reviews");
      for (const group of ["performerReviews", "bookerReviews"]) { const reviews = await db.collectionGroup(group).get(); for (const doc of reviews.docs) { const data = doc.data() as Data; if (client) await client.query(`INSERT INTO reviews (id,reviewee_id,booker_id,performer_id,booking_id,occurred_at,overall_rating,overall_review,review_type,profile,created_at,updated_at) VALUES ($1,$12,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10,$11) ON CONFLICT (id,review_type,reviewee_id) DO UPDATE SET booker_id=EXCLUDED.booker_id,performer_id=EXCLUDED.performer_id,booking_id=EXCLUDED.booking_id,occurred_at=EXCLUDED.occurred_at,overall_rating=EXCLUDED.overall_rating,overall_review=EXCLUDED.overall_review,review_type=EXCLUDED.review_type,profile=EXCLUDED.profile`, [doc.id,group === "bookerReviews" ? doc.ref.parent.parent!.id : text(data.bookerId),group === "performerReviews" ? doc.ref.parent.parent!.id : text(data.performerId),text(data.bookingId),time(data.timestamp),typeof data.overallRating === "number" ? data.overallRating : null,text(data.overallReview) ?? "",group === "performerReviews" ? "performer" : "booker",JSON.stringify(profile(data,["id","bookerId","performerId","bookingId","timestamp","overallRating","overallReview","type"])),doc.createTime?.toDate(),doc.updateTime?.toDate(),doc.ref.parent.parent!.id]); counts.reviews++; } }
      if (client) await client.query("COMMIT");
    } catch (error) { if (client) await client.query("ROLLBACK"); throw error; } finally { client?.release(); }
  } finally { await pool?.end(); }
  console.log(JSON.stringify({ mode: apply ? "apply" : "dry-run", ...counts }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });

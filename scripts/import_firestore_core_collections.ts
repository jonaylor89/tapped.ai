import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { FieldPath, GeoPoint, Timestamp, getFirestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { createHash } from "node:crypto";
import { Pool } from "pg";
import { requireDatabaseUrl } from "./helpers/database";

const app =
  getApps()[0] ??
  initializeApp({
    credential: process.env.GOOGLE_APPLICATION_CREDENTIALS
      ? applicationDefault()
      : cert(require("./in-the-loop-306520-firebase-adminsdk-60hh4-b0eb65b2df.json")),
  });
const db = getFirestore(app);

const COLLECTIONS = ["services", "bookings", "activities", "deviceTokens", "apiKeys"] as const;
type CollectionName = (typeof COLLECTIONS)[number];
type Data = Record<string, unknown>;
type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

type Options = {
  apply: boolean;
  batchSize: number;
  collections: CollectionName[];
  limit?: number;
};

type Report = {
  scanned: number;
  written: number;
  invalidLocations: number;
  missingTokenOwners: number;
};

const DEFAULT_BATCH_SIZE = 500;
const SHA_256_HEX = /^[a-f0-9]{64}$/;

const UPSERTS: Record<CollectionName, string> = {
  services: `
    INSERT INTO services (id, user_id, title, description, rate, rate_type, count, deleted, profile, created_at, updated_at)
    SELECT id, user_id, title, description, rate, rate_type, count, deleted, profile, created_at, updated_at
    FROM jsonb_to_recordset($1::jsonb) AS rows(
      id text, user_id text, title text, description text, rate numeric, rate_type text, count integer,
      deleted boolean, profile jsonb, created_at timestamptz, updated_at timestamptz
    )
    ON CONFLICT (id) DO UPDATE SET
      user_id = EXCLUDED.user_id, title = EXCLUDED.title, description = EXCLUDED.description,
      rate = EXCLUDED.rate, rate_type = EXCLUDED.rate_type, count = EXCLUDED.count, deleted = EXCLUDED.deleted,
      profile = EXCLUDED.profile, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at
  `,
  bookings: `
    INSERT INTO bookings (
      id, service_id, added_by_user, name, note, requester_id, requestee_id, status, genres, rate,
      start_time, end_time, occurred_at, location, place_id, tickets_sold, total_event_revenue,
      flier_url, event_url, reference_event_id, profile, created_at, updated_at
    )
    SELECT
      id, service_id, added_by_user, name, note, requester_id, requestee_id, status, genres, rate,
      start_time, end_time, occurred_at,
      CASE WHEN longitude IS NULL OR latitude IS NULL THEN NULL
        ELSE ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography END,
      place_id, tickets_sold, total_event_revenue, flier_url, event_url, reference_event_id,
      profile, created_at, updated_at
    FROM jsonb_to_recordset($1::jsonb) AS rows(
      id text, service_id text, added_by_user boolean, name text, note text, requester_id text,
      requestee_id text, status text, genres text[], rate numeric, start_time timestamptz,
      end_time timestamptz, occurred_at timestamptz, longitude double precision, latitude double precision,
      place_id text, tickets_sold integer, total_event_revenue numeric, flier_url text, event_url text,
      reference_event_id text, profile jsonb, created_at timestamptz, updated_at timestamptz
    )
    ON CONFLICT (id) DO UPDATE SET
      service_id = EXCLUDED.service_id, added_by_user = EXCLUDED.added_by_user, name = EXCLUDED.name,
      note = EXCLUDED.note, requester_id = EXCLUDED.requester_id, requestee_id = EXCLUDED.requestee_id,
      status = EXCLUDED.status, genres = EXCLUDED.genres, rate = EXCLUDED.rate, start_time = EXCLUDED.start_time,
      end_time = EXCLUDED.end_time, occurred_at = EXCLUDED.occurred_at, location = EXCLUDED.location,
      place_id = EXCLUDED.place_id, tickets_sold = EXCLUDED.tickets_sold,
      total_event_revenue = EXCLUDED.total_event_revenue, flier_url = EXCLUDED.flier_url,
      event_url = EXCLUDED.event_url, reference_event_id = EXCLUDED.reference_event_id,
      profile = EXCLUDED.profile, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at
  `,
  activities: `
    INSERT INTO activities (
      id, activity_type, from_user_id, to_user_id, booking_id, loop_id, comment_id, root_id, count,
      marked_read, occurred_at, profile, created_at, updated_at
    )
    SELECT id, activity_type, from_user_id, to_user_id, booking_id, loop_id, comment_id, root_id, count,
      marked_read, occurred_at, profile, created_at, updated_at
    FROM jsonb_to_recordset($1::jsonb) AS rows(
      id text, activity_type text, from_user_id text, to_user_id text, booking_id text, loop_id text,
      comment_id text, root_id text, count integer, marked_read boolean, occurred_at timestamptz,
      profile jsonb, created_at timestamptz, updated_at timestamptz
    )
    ON CONFLICT (id) DO UPDATE SET
      activity_type = EXCLUDED.activity_type, from_user_id = EXCLUDED.from_user_id,
      to_user_id = EXCLUDED.to_user_id, booking_id = EXCLUDED.booking_id, loop_id = EXCLUDED.loop_id,
      comment_id = EXCLUDED.comment_id, root_id = EXCLUDED.root_id, count = EXCLUDED.count,
      marked_read = EXCLUDED.marked_read, occurred_at = EXCLUDED.occurred_at,
      profile = EXCLUDED.profile, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at
  `,
  deviceTokens: `
    INSERT INTO device_tokens (token, user_id, platform, profile, created_at, updated_at)
    SELECT token, user_id, platform, profile, created_at, updated_at
    FROM jsonb_to_recordset($1::jsonb) AS rows(
      token text, user_id text, platform text, profile jsonb, created_at timestamptz, updated_at timestamptz
    )
    ON CONFLICT (token) DO UPDATE SET
      user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, profile = EXCLUDED.profile,
      created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at
  `,
  apiKeys: `
    INSERT INTO api_keys (key_hash, user_id, profile, created_at, updated_at)
    SELECT key_hash, user_id, profile, created_at, updated_at
    FROM jsonb_to_recordset($1::jsonb) AS rows(
      key_hash char(64), user_id text, profile jsonb, created_at timestamptz, updated_at timestamptz
    )
    ON CONFLICT (key_hash) DO UPDATE SET
      user_id = EXCLUDED.user_id, profile = EXCLUDED.profile, created_at = EXCLUDED.created_at,
      updated_at = EXCLUDED.updated_at
  `,
};

function parseOptions(args: string[]): Options {
  const options: Options = { apply: false, batchSize: DEFAULT_BATCH_SIZE, collections: [...COLLECTIONS] };
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--apply") options.apply = true;
    else if (argument === "--dry-run") options.apply = false;
    else if (argument === "--batch-size") options.batchSize = positiveInteger(args[++index], "--batch-size");
    else if (argument === "--limit") options.limit = positiveInteger(args[++index], "--limit");
    else if (argument === "--collections") {
      const values = args[++index]?.split(",") ?? [];
      if (values.length === 0 || values.some((value) => !COLLECTIONS.includes(value as CollectionName))) {
        throw new Error(`--collections must be a comma-separated subset of ${COLLECTIONS.join(", ")}`);
      }
      options.collections = values as CollectionName[];
    } else if (argument === "--help") {
      console.log(`Usage: npx ts-node import_firestore_core_collections.ts [options]

Dry run is the default. --apply writes Postgres and requires DATABASE_URL.

Options:
  --apply
  --dry-run
  --collections <services,bookings,activities,deviceTokens,apiKeys>
  --batch-size <number> (default: ${DEFAULT_BATCH_SIZE})
  --limit <number>`);
      process.exit(0);
    } else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

function positiveInteger(value: string | undefined, option: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${option} requires a positive integer`);
  return parsed;
}

function isRecord(value: unknown): value is Data {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function string(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function number(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function nullableInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function timestamp(value: unknown): string | null {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

function profile(value: unknown): Json | undefined {
  if (value === null) return null;
  if (typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value : String(value);
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (value instanceof GeoPoint) return { latitude: value.latitude, longitude: value.longitude };
  if (Buffer.isBuffer(value)) return { base64: value.toString("base64") };
  if (Array.isArray(value)) return value.flatMap((entry) => {
    const normalized = profile(entry);
    return normalized === undefined ? [] : [normalized];
  });
  if (isRecord(value)) {
    if (typeof value.path === "string" && "firestore" in value) return { path: value.path };
    const result: { [key: string]: Json } = {};
    for (const [key, entry] of Object.entries(value)) {
      const normalized = profile(entry);
      if (normalized !== undefined) result[key] = normalized;
    }
    return result;
  }
  return undefined;
}

function remainingProfile(data: Data, promoted: string[]): { [key: string]: Json } {
  const result: { [key: string]: Json } = {};
  const promotedFields = new Set(promoted);
  for (const [key, value] of Object.entries(data)) {
    if (promotedFields.has(key)) continue;
    const normalized = profile(value);
    if (normalized !== undefined) result[key] = normalized;
  }
  return result;
}

function sourceTimes(document: QueryDocumentSnapshot): { createdAt: string; updatedAt: string } {
  const fallback = new Date().toISOString();
  return {
    createdAt: document.createTime?.toDate().toISOString() ?? fallback,
    updatedAt: document.updateTime?.toDate().toISOString() ?? fallback,
  };
}

function coordinates(data: Data): { latitude: number | null; longitude: number | null; placeId: string | null; valid: boolean } {
  const location = isRecord(data.location) ? data.location : undefined;
  const latitude = location?.latitude ?? location?.lat ?? data.lat;
  const longitude = location?.longitude ?? location?.lng ?? data.lng;
  const valid =
    typeof latitude === "number" && Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
    typeof longitude === "number" && Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;
  return {
    latitude: valid ? latitude : null,
    longitude: valid ? longitude : null,
    placeId: nullableString(data.placeId) ?? nullableString(location?.placeId),
    valid,
  };
}

function serviceRow(document: QueryDocumentSnapshot): Data {
  const data = document.data() as Data;
  const times = sourceTimes(document);
  return {
    id: document.id,
    user_id: nullableString(data.userId) ?? (document.ref.parent.id === "userServices" ? document.ref.parent.parent?.id : null),
    title: string(data.title),
    description: string(data.description),
    rate: number(data.rate),
    rate_type: nullableString(data.rateType),
    count: nullableInteger(data.count) ?? 0,
    deleted: data.deleted === true,
    profile: remainingProfile(data, ["id", "userId", "title", "description", "rate", "rateType", "count", "deleted"]),
    created_at: times.createdAt,
    updated_at: times.updatedAt,
  };
}

function bookingRow(document: QueryDocumentSnapshot, report: Report): Data {
  const data = document.data() as Data;
  const times = sourceTimes(document);
  const location = coordinates(data);
  if ((data.location !== undefined || data.lat !== undefined || data.lng !== undefined) && !location.valid) report.invalidLocations += 1;
  const genres = Array.isArray(data.genres) ? data.genres.filter((genre): genre is string => typeof genre === "string") : [];
  return {
    id: document.id,
    service_id: nullableString(data.serviceId),
    added_by_user: data.addedByUser === true,
    name: string(data.name),
    note: string(data.note),
    requester_id: nullableString(data.requesterId),
    requestee_id: nullableString(data.requesteeId),
    status: string(data.status) || "confirmed",
    genres,
    rate: number(data.rate),
    start_time: timestamp(data.startTime),
    end_time: timestamp(data.endTime),
    occurred_at: timestamp(data.timestamp),
    longitude: location.longitude,
    latitude: location.latitude,
    place_id: location.placeId,
    tickets_sold: nullableInteger(data.ticketsSold),
    total_event_revenue: typeof data.totalEventRevenue === "number" && Number.isFinite(data.totalEventRevenue) ? data.totalEventRevenue : null,
    flier_url: nullableString(data.flierUrl),
    event_url: nullableString(data.eventUrl),
    reference_event_id: nullableString(data.referenceEventId),
    profile: remainingProfile(data, [
      "id", "serviceId", "addedByUser", "name", "note", "requesterId", "requesteeId", "status", "genres", "rate",
      "startTime", "endTime", "timestamp", "location", "lat", "lng", "placeId", "ticketsSold", "totalEventRevenue",
      "flierUrl", "eventUrl", "referenceEventId",
    ].filter(field => location.valid || !["location", "lat", "lng"].includes(field))),
    created_at: times.createdAt,
    updated_at: times.updatedAt,
  };
}

function activityRow(document: QueryDocumentSnapshot): Data {
  const data = document.data() as Data;
  const times = sourceTimes(document);
  return {
    id: document.id,
    activity_type: string(data.type),
    from_user_id: nullableString(data.fromUserId),
    to_user_id: nullableString(data.toUserId),
    booking_id: nullableString(data.bookingId),
    loop_id: nullableString(data.loopId),
    comment_id: nullableString(data.commentId),
    root_id: nullableString(data.rootId),
    count: nullableInteger(data.count) ?? 0,
    marked_read: data.markedRead === true,
    occurred_at: timestamp(data.timestamp),
    profile: remainingProfile(data, ["id", "type", "fromUserId", "toUserId", "bookingId", "loopId", "commentId", "rootId", "count", "markedRead", "timestamp"]),
    created_at: times.createdAt,
    updated_at: times.updatedAt,
  };
}

function deviceTokenRow(document: QueryDocumentSnapshot, report: Report): Data | undefined {
  const data = document.data() as Data;
  const userId = document.ref.parent.parent?.id;
  if (!userId) {
    report.missingTokenOwners += 1;
    return undefined;
  }
  const times = sourceTimes(document);
  const token = nullableString(data.token) ?? document.id;
  return {
    token,
    user_id: userId,
    platform: nullableString(data.platform),
    profile: remainingProfile(data, ["token", "platform"]),
    created_at: times.createdAt,
    updated_at: times.updatedAt,
  };
}

function apiKeyRow(document: QueryDocumentSnapshot): Data {
  const data = document.data() as Data;
  const sourceKey = nullableString(data.key) ?? document.id;
  const keyHash = SHA_256_HEX.test(sourceKey) && document.id === sourceKey
    ? sourceKey
    : createHash("sha256").update(sourceKey).digest("hex");
  const times = sourceTimes(document);
  return {
    key_hash: keyHash,
    user_id: string(data.userId),
    profile: remainingProfile(data, ["key", "userId", "timestamp"]),
    created_at: timestamp(data.timestamp) ?? times.createdAt,
    updated_at: times.updatedAt,
  };
}

function collectionQuery(name: CollectionName) {
  return name === "deviceTokens" ? db.collectionGroup("tokens") : db.collection(name);
}

function rowForDocument(name: CollectionName, document: QueryDocumentSnapshot, report: Report): Data | undefined {
  switch (name) {
    case "services": return serviceRow(document);
    case "bookings": return bookingRow(document, report);
    case "activities": return activityRow(document);
    case "deviceTokens": return deviceTokenRow(document, report);
    case "apiKeys": return apiKeyRow(document);
  }
}

async function importCollection(name: CollectionName, options: Options, pool: Pool | undefined, nestedServices = false): Promise<Report> {
  const report: Report = { scanned: 0, written: 0, invalidLocations: 0, missingTokenOwners: 0 };
  let cursor: QueryDocumentSnapshot | undefined;

  while (options.limit === undefined || report.scanned < options.limit) {
    const remaining = options.limit === undefined ? options.batchSize : options.limit - report.scanned;
    let query = (nestedServices ? db.collectionGroup("userServices") : collectionQuery(name)).orderBy(FieldPath.documentId()).limit(Math.min(options.batchSize, remaining));
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;

    const mappedRows = page.docs.flatMap((document) => {
      const row = rowForDocument(name, document, report);
      return row ? [row] : [];
    });
    // The same FCM token can exist under both legacy `users/{uid}/tokens` and
    // `device_tokens/{uid}/tokens` paths. One upsert statement cannot update it twice.
    const rows = name === "deviceTokens"
      ? [...new Map(mappedRows.map((row) => [String(row.token), row])).values()]
      : mappedRows;
    if (pool && rows.length > 0) {
      await pool.query(UPSERTS[name], [JSON.stringify(rows)]);
      report.written += rows.length;
    }
    report.scanned += page.size;
    cursor = page.docs[page.docs.length - 1];
    console.error(JSON.stringify({ collection: name, mode: options.apply ? "apply" : "dry-run", ...report }));
    if (page.size < Math.min(options.batchSize, remaining)) break;
  }
  return report;
}

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  const pool = options.apply ? new Pool({ connectionString: requireDatabaseUrl(), max: 1 }) : undefined;
  try {
    for (const collection of options.collections) {
      const report = await importCollection(collection, options, pool);
      console.log(JSON.stringify({ collection, mode: options.apply ? "apply" : "dry-run", ...report }, null, 2));
      if (collection === "services") console.log(JSON.stringify({ collection: "userServices", ...await importCollection(collection, options, pool, true) }));
    }
  } finally {
    await pool?.end();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});

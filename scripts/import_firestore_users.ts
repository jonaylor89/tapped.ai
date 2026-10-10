import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { FieldPath, GeoPoint, Timestamp, getFirestore } from "firebase-admin/firestore";
import { Pool, type PoolClient } from "pg";
import { requireDatabaseUrl } from "./helpers/database";

const app =
  getApps()[0] ??
  initializeApp({
    credential: process.env.GOOGLE_APPLICATION_CREDENTIALS
      ? applicationDefault()
      : cert(require("./in-the-loop-306520-firebase-adminsdk-60hh4-b0eb65b2df.json")),
  });
const usersRef = getFirestore(app).collection("users");

type Options = {
  apply: boolean;
  batchSize: number;
  limit?: number;
  resumeAfter?: string;
};

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type RecordValue = Record<string, unknown>;

type UserRow = {
  id: string;
  username: string;
  email: string;
  artistName: string;
  bio: string;
  occupations: string[];
  profilePicture: string | null;
  latitude: number | null;
  longitude: number | null;
  placeId: string | null;
  deleted: boolean;
  shadowBanned: boolean;
  unclaimed: boolean;
  profile: string;
  createdAt: Date;
  updatedAt: Date;
};

type Report = {
  processed: number;
  insertedOrUpdated: number;
  invalidLocations: number;
  invalidOccupations: number;
  missingUsernames: number;
  lastId?: string;
};

const DEFAULT_BATCH_SIZE = 250;

const UPSERT_USER = `
  INSERT INTO users (
    id, username, email, artist_name, bio, occupations, profile_picture, location, place_id,
    deleted, shadow_banned, unclaimed, profile, created_at, updated_at
  ) VALUES (
    $1, $2, $3, $4, $5, $6, $7,
    CASE
      WHEN $8::double precision IS NULL OR $9::double precision IS NULL THEN NULL
      ELSE ST_SetSRID(ST_MakePoint($8, $9), 4326)::geography
    END,
    $10, $11, $12, $13, $14::jsonb, $15, $16
  ) ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    artist_name = EXCLUDED.artist_name,
    bio = EXCLUDED.bio,
    occupations = EXCLUDED.occupations,
    profile_picture = EXCLUDED.profile_picture,
    location = EXCLUDED.location,
    place_id = EXCLUDED.place_id,
    deleted = EXCLUDED.deleted,
    shadow_banned = EXCLUDED.shadow_banned,
    unclaimed = EXCLUDED.unclaimed,
    profile = EXCLUDED.profile,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at
`;

function parseOptions(args: string[]): Options {
  const options: Options = { apply: false, batchSize: DEFAULT_BATCH_SIZE };

  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--apply") {
      options.apply = true;
    } else if (argument === "--dry-run") {
      options.apply = false;
    } else if (argument === "--batch-size") {
      options.batchSize = parsePositiveInteger(args[++index], "--batch-size");
    } else if (argument === "--limit") {
      options.limit = parsePositiveInteger(args[++index], "--limit");
    } else if (argument === "--resume-after") {
      const value = args[++index];
      if (!value) {
        throw new Error("--resume-after requires a Firestore document ID");
      }
      options.resumeAfter = value;
    } else if (argument === "--help") {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }

  return options;
}

function parsePositiveInteger(value: string | undefined, argument: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${argument} requires a positive integer`);
  }
  return number;
}

function printUsage(): void {
  console.log(`Usage: npx ts-node import_firestore_users.ts [options]

Reads Firestore users in document-ID order. Dry run is the default and never opens Postgres.

Options:
  --apply                  Upsert users into Postgres (requires DATABASE_URL)
  --dry-run                Report conversion results without writing (default)
  --batch-size <number>    Firestore page and Postgres transaction size (default: ${DEFAULT_BATCH_SIZE})
  --limit <number>         Stop after this many users
  --resume-after <uid>     Resume after a Firestore document ID
  --help                   Show this help`);
}

function isRecord(value: unknown): value is RecordValue {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function booleanValue(value: unknown): boolean {
  return value === true;
}

function timestampValue(value: unknown): Date | undefined {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  return undefined;
}

function normaliseJson(value: unknown): Json | undefined {
  if (value === null) {
    return null;
  }
  if (typeof value === "string" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : String(value);
  }
  if (value instanceof Timestamp) {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (value instanceof GeoPoint) {
    return { latitude: value.latitude, longitude: value.longitude };
  }
  if (Buffer.isBuffer(value)) {
    return { base64: value.toString("base64") };
  }
  if (Array.isArray(value)) {
    return value.flatMap((entry) => {
      const normalised = normaliseJson(entry);
      return normalised === undefined ? [] : [normalised];
    });
  }
  if (isRecord(value)) {
    if (typeof value.path === "string" && "firestore" in value) {
      return { path: value.path };
    }
    const result: { [key: string]: Json } = {};
    for (const [key, entry] of Object.entries(value)) {
      const normalised = normaliseJson(entry);
      if (normalised !== undefined) {
        result[key] = normalised;
      }
    }
    return result;
  }
  return value === undefined ? undefined : String(value);
}

function locationValue(value: unknown): {
  latitude: number | null;
  longitude: number | null;
  placeId: string | null;
  valid: boolean;
} {
  if (!isRecord(value)) {
    return { latitude: null, longitude: null, placeId: null, valid: value === undefined || value === null };
  }

  const latitude = value.latitude ?? value.lat;
  const longitude = value.longitude ?? value.lng;
  const placeId = nullableString(value.placeId);
  const isValid =
    typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180;

  return {
    latitude: isValid ? latitude : null,
    longitude: isValid ? longitude : null,
    placeId,
    valid: isValid,
  };
}

function profileForUser(data: RecordValue, keepLocation: boolean): Json {
  const promotedFields = new Set([
    "email",
    "username",
    "artistName",
    "bio",
    "occupations",
    "profilePicture",
    "placeId",
    "deleted",
    "shadowBanned",
    "unclaimed",
  ]);
  if (!keepLocation) {
    promotedFields.add("location");
  }

  const profile: { [key: string]: Json } = {};
  for (const [key, value] of Object.entries(data)) {
    if (promotedFields.has(key)) {
      continue;
    }
    const normalised = normaliseJson(value);
    if (normalised !== undefined) {
      profile[key] = normalised;
    }
  }
  return profile;
}

function userRow(id: string, data: RecordValue, createdAt: Date, updatedAt: Date, report: Report): UserRow {
  const rawLocation = data.location;
  const location = locationValue(rawLocation);
  const occupations = Array.isArray(data.occupations)
    ? data.occupations.filter((occupation): occupation is string => typeof occupation === "string")
    : [];

  if (data.location !== undefined && data.location !== null && !location.valid) {
    report.invalidLocations += 1;
  }
  if (data.occupations !== undefined && !Array.isArray(data.occupations)) {
    report.invalidOccupations += 1;
  }
  if (!stringValue(data.username)) {
    report.missingUsernames += 1;
  }

  return {
    id,
    username: stringValue(data.username),
    email: stringValue(data.email),
    artistName: stringValue(data.artistName),
    bio: stringValue(data.bio),
    occupations,
    profilePicture: nullableString(data.profilePicture),
    latitude: location.latitude,
    longitude: location.longitude,
    placeId: nullableString(data.placeId) ?? location.placeId,
    deleted: booleanValue(data.deleted),
    shadowBanned: booleanValue(data.shadowBanned),
    unclaimed: booleanValue(data.unclaimed),
    profile: JSON.stringify(profileForUser(data, !location.valid)),
    createdAt,
    updatedAt,
  };
}

async function upsertUsers(client: PoolClient, users: UserRow[]): Promise<void> {
  await client.query("BEGIN");
  try {
    for (const user of users) {
      await client.query(UPSERT_USER, [
        user.id,
        user.username,
        user.email,
        user.artistName,
        user.bio,
        user.occupations,
        user.profilePicture,
        user.longitude,
        user.latitude,
        user.placeId,
        user.deleted,
        user.shadowBanned,
        user.unclaimed,
        user.profile,
        user.createdAt,
        user.updatedAt,
      ]);
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  }
}

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  const report: Report = {
    processed: 0,
    insertedOrUpdated: 0,
    invalidLocations: 0,
    invalidOccupations: 0,
    missingUsernames: 0,
  };
  const pool = options.apply ? new Pool({ connectionString: requireDatabaseUrl(), max: 1 }) : undefined;
  let resumeAfter = options.resumeAfter;

  try {
    while (options.limit === undefined || report.processed < options.limit) {
      const remaining = options.limit === undefined ? options.batchSize : options.limit - report.processed;
      let query = usersRef.orderBy(FieldPath.documentId()).limit(Math.min(options.batchSize, remaining));
      if (resumeAfter) {
        query = query.startAfter(resumeAfter);
      }

      const page = await query.get();
      if (page.empty) {
        break;
      }

      const rows = page.docs.map((document) => {
        const data = document.data() as RecordValue;
        const fallbackTimestamp = timestampValue(data.timestamp) ?? new Date();
        return userRow(
          document.id,
          data,
          document.createTime?.toDate() ?? fallbackTimestamp,
          document.updateTime?.toDate() ?? fallbackTimestamp,
          report,
        );
      });

      if (pool) {
        const client = await pool.connect();
        try {
          await upsertUsers(client, rows);
        } finally {
          client.release();
        }
        report.insertedOrUpdated += rows.length;
      }

      report.processed += rows.length;
      resumeAfter = page.docs[page.docs.length - 1].id;
      report.lastId = resumeAfter;
      console.error(JSON.stringify({ mode: options.apply ? "apply" : "dry-run", ...report }));

      if (page.size < Math.min(options.batchSize, remaining)) {
        break;
      }
    }
  } finally {
    await pool?.end();
  }

  console.log(JSON.stringify({ mode: options.apply ? "apply" : "dry-run", ...report }, null, 2));
  if (!options.apply) {
    console.log("Dry run complete. Re-run with --apply to write these users to Postgres.");
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});

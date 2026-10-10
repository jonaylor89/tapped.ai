import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { createClient } from "redis";

const app =
  getApps()[0] ??
  initializeApp({
    credential: process.env.GOOGLE_APPLICATION_CREDENTIALS
      ? applicationDefault()
      : cert(require("./in-the-loop-306520-firebase-adminsdk-60hh4-b0eb65b2df.json")),
  });
const db = getFirestore(app);
const TTL_SECONDS = 90 * 24 * 60 * 60;
const BATCH_SIZE = 500;

type Data = Record<string, unknown>;

type Options = { apply: boolean };

function options(args: string[]): Options {
  if (args.length === 0 || (args.length === 1 && args[0] === "--dry-run")) return { apply: false };
  if (args.length === 1 && args[0] === "--apply") return { apply: true };
  throw new Error("Usage: npx ts-node seed_firestore_places_cache_to_redis.ts [--dry-run|--apply]");
}

function isRecord(value: unknown): value is Data {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function string(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function number(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function addressComponents(value: unknown): Data[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((component) => ({
    longText: string(component.longText) ?? string(component.longName) ?? null,
    shortText: string(component.shortText) ?? string(component.shortName) ?? null,
    types: Array.isArray(component.types) ? component.types.filter((type): type is string => typeof type === "string") : [],
  }));
}

function photoMetadata(value: unknown): Data | null {
  if (!isRecord(value)) return null;
  const name = string(value.name) ?? string(value.photoReference);
  if (!name) return null;
  return { name, widthPx: number(value.width), heightPx: number(value.height) };
}

function place(documentId: string, data: Data): Data | undefined {
  const placeId = string(data.placeId) ?? documentId;
  const lat = number(data.lat);
  const lng = number(data.lng);
  if (lat === undefined || lng === undefined || lat < -90 || lat > 90 || lng < -180 || lng > 180) return undefined;
  const metadata = photoMetadata(data.photoMetadata);
  const photoNames = Array.isArray(data.photoNames)
    ? data.photoNames.filter((name): name is string => typeof name === "string")
    : metadata?.name ? [metadata.name as string] : [];
  return {
    placeId,
    name: string(data.name) ?? null,
    shortFormattedAddress: string(data.shortFormattedAddress) ?? null,
    lat,
    lng,
    locality: string(data.locality) ?? null,
    photoNames,
    addressComponents: addressComponents(data.addressComponents),
    photoMetadata: metadata,
    geohash: string(data.geohash) ?? null,
  };
}

async function main(): Promise<void> {
  const { apply } = options(process.argv.slice(2));
  const redisUrl = process.env.REDIS_URL;
  if (!redisUrl) throw new Error("REDIS_URL is required");
  const redis = createClient({ url: redisUrl });
  if (apply) await redis.connect();

  let scanned = 0;
  let seeded = 0;
  let invalid = 0;
  let cursor: QueryDocumentSnapshot | undefined;
  try {
    while (true) {
      let query = db.collection("googlePlacesCache").orderBy(FieldPath.documentId()).limit(BATCH_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      const entries = page.docs.flatMap((document) => {
        const value = place(document.id, document.data() as Data);
        if (!value) {
          invalid += 1;
          return [];
        }
        return [[`places:details:${value.placeId as string}`, JSON.stringify(value)] as const];
      });
      if (apply && entries.length > 0) {
        const transaction = redis.multi();
        for (const [key, value] of entries) transaction.setEx(key, TTL_SECONDS, value);
        await transaction.exec();
        seeded += entries.length;
      }
      scanned += page.size;
      cursor = page.docs[page.docs.length - 1];
      console.error(JSON.stringify({ mode: apply ? "apply" : "dry-run", scanned, seeded, invalid }));
      if (page.size < BATCH_SIZE) break;
    }
  } finally {
    if (apply) await redis.quit();
  }
  console.log(JSON.stringify({ mode: apply ? "apply" : "dry-run", scanned, seeded, invalid, ttlSeconds: TTL_SECONDS }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});

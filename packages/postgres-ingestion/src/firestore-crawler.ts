import { deliveryKey, type ObservationInput, record, text } from "./observations";

export const FIRESTORE_CRAWLER_PARSER = "firestore-crawler-v1";
export function firestoreRunId(project: string, path: string): string {
  return `firestore-run-${deliveryKey(project, path)}`;
}

/** Firestore SDK-independent adapter: document paths/versions are durable import identities. */
export function firestoreObservation(
  project: string,
  document: { path: string; version: string; updatedAt: string; data: Record<string, unknown> },
  evidenceLine: number,
): ObservationInput {
  const parts = document.path.split("/");
  const history =
    parts.length === 6 && parts[0] === "rawScrapeData" && parts[2] === "scrapeRuns" && parts[4] === "scrapeResults";
  if (!history && !(parts.length === 2 && parts[0] === "crawler")) throw new Error("Unsupported crawler document path");
  const info = record(document.data.crawlerInfo);
  const url = text(document.data.url);
  const key = url ? encodeURIComponent(url) : `firestore:${parts[5]}`;
  return {
    source: history ? "legacy-scrapers" : "event-crawler",
    sourceKey: history ? (key.length <= 4096 ? key : `url-sha256:${deliveryKey(url ?? key)}`) : parts[1],
    deliveryKey: deliveryKey(project, document.path, document.version, FIRESTORE_CRAWLER_PARSER),
    // Firestore's update version, not a potentially stale embedded crawler timestamp, determines
    // snapshot ordering. Original nanoseconds and crawler metadata remain in archived evidence.
    observedAt: document.updatedAt,
    parserVersion: FIRESTORE_CRAWLER_PARSER,
    venueId: history ? parts[1] : text(record(document.data.venue).id),
    runId: history ? firestoreRunId(project, parts.slice(0, 4).join("/")) : null,
    legacyRunId: history ? parts[3] : text(info.runId),
    evidenceLine,
    materialize: !history,
    data: document.data,
  };
}

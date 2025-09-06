import { Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";
import { db } from "../utils/firebase.js";
import { EventData, UserModel } from "../types.js";

// Legacy types from webscrapers
interface LegacyScrapedEventData {
  id: string;
  isMusicEvent: boolean | undefined;
  url: string;
  title: string | null;
  description: string | null;
  artists: string[];
  ticketPrice: number | null | undefined;
  doorPrice: number | null | undefined;
  startTime: Date | Timestamp | string;
  endTime: Date | Timestamp | string;
  flierUrl: string | null;
}

interface LegacyRunData {
  id: string;
  startTime: Timestamp;
  endTime?: Timestamp | null;
  error: string | null;
  name?: string;
  url?: string;
  sitemap?: string;
  venue?: UserModel;
  location?: any;
}

const crawlerRef = db.collection("crawler");
const rawScrapeDataRef = db.collection("rawScrapeData");
const usersRef = db.collection("users");

// Failed run configurations - update these with your specific failed runIds
const FAILED_RUN_IDS: string[] = [
  // "ryhpDnXVjCS3nTrXNHzR",
  // "urMHwf5DeUlKMgxlHk0x",
];

interface FailedRun {
  scraperId: string;
  runId: string;
}

/**
 * Find scrapers that contain the specified runIds
 */
async function findFailedRuns(runIds: string[]): Promise<FailedRun[]> {
  console.log(`[+] Searching for runIds: ${runIds.join(", ")}`);

  const failedRuns: FailedRun[] = [];
  const scraperDocs = await rawScrapeDataRef.get();

  for (const scraperDoc of scraperDocs.docs) {
    const scraperId = scraperDoc.id;
    console.log(`[+] Checking scraper: ${scraperId}`);

    // Get all runs for this scraper
    const runsSnapshot = await rawScrapeDataRef
      .doc(scraperId)
      .collection("scrapeRuns")
      .get();

    for (const runDoc of runsSnapshot.docs) {
      const runId = runDoc.id;

      if (runIds.includes(runId)) {
        console.log(`[+] Found runId ${runId} in scraper ${scraperId}`);
        failedRuns.push({ scraperId, runId });
      }
    }
  }

  console.log(`[+] Found ${failedRuns.length} matching runs`);
  return failedRuns;
}

/**
 * Migrate specific failed runs
 */
export async function migrateSpecificRuns(
  failedRuns: FailedRun[],
  dryRun: boolean = true,
): Promise<void> {
  console.log(`[+] Starting specific run migration (dry run: ${dryRun})`);
  console.log(`[+] Processing ${failedRuns.length} failed runs`);

  let totalEvents = 0;
  let errors = 0;

  try {
    for (const failedRun of failedRuns) {
      const { scraperId, runId } = failedRun;

      console.log(`[+] Processing scraper: ${scraperId}, run: ${runId}`);

      // Get the venue information
      const venue = await getVenueById(scraperId);
      if (!venue) {
        console.error(`[!] No venue found for scraper ID: ${scraperId}`);
        continue;
      }

      // Get the specific run data
      const runDoc = await rawScrapeDataRef
        .doc(scraperId)
        .collection("scrapeRuns")
        .doc(runId)
        .get();

      if (!runDoc.exists) {
        console.error(`[!] Run ${runId} not found for scraper ${scraperId}`);
        continue;
      }

      const runData = runDoc.data() as LegacyRunData;

      // Get all scrape results for this specific run
      const resultsSnapshot = await rawScrapeDataRef
        .doc(scraperId)
        .collection("scrapeRuns")
        .doc(runId)
        .collection("scrapeResults")
        .get();

      console.log(`[+] Found ${resultsSnapshot.size} events in run ${runId}`);

      for (const resultDoc of resultsSnapshot.docs) {
        try {
          const legacyEventData = resultDoc.data() as LegacyScrapedEventData;

          // Validate required data
          if (!legacyEventData.startTime || !legacyEventData.endTime) {
            console.warn(
              `[!] Skipping event with missing dates: ${legacyEventData.id}`,
            );
            continue;
          }

          // Transform legacy data to new schema
          const newEventData = transformLegacyEventData(
            legacyEventData,
            venue,
            runId,
            runData.startTime.toDate(),
          );

          if (!dryRun) {
            // Save to new crawler collection
            const encodedLink = encodeURIComponent(newEventData.url || "");
            await crawlerRef.doc(encodedLink).set(
              {
                ...newEventData,
                startTime: Timestamp.fromDate(newEventData.startTime),
                endTime: Timestamp.fromDate(newEventData.endTime),
                crawlerInfo: {
                  ...newEventData.crawlerInfo,
                  timestamp: Timestamp.fromDate(
                    newEventData.crawlerInfo.timestamp,
                  ),
                },
              },
              { merge: true },
            );

            console.log(
              `[+] Migrated event: ${newEventData.title} (${encodedLink})`,
            );
          } else {
            console.log(`[DRY RUN] Would migrate event: ${newEventData.title}`);
          }

          totalEvents++;
        } catch (error) {
          console.error(
            `[!] Error processing event in run ${runId} for ${scraperId}:`,
            error,
          );
          console.error(
            "[!] Event data:",
            JSON.stringify(
              {
                id: resultDoc.id,
                data: resultDoc.data(),
              },
              null,
              2,
            ),
          );
          errors++;
        }
      }
    }

    console.log("[+] Specific run migration complete!");
    console.log(`    - Total events processed: ${totalEvents}`);
    console.log(`    - Errors: ${errors}`);
  } catch (error) {
    console.error("[!] Migration failed:", error);
    throw error;
  }
}

/**
 * Transform legacy event data to new schema with better error handling
 */
function transformLegacyEventData(
  legacyData: LegacyScrapedEventData,
  venue: UserModel,
  runId: string,
  runTimestamp: Date,
): EventData {
  const encodedLink = encodeURIComponent(legacyData.url);

  // Convert Timestamps to Dates if needed
  let startTime: Date;
  let endTime: Date;

  try {
    if (legacyData.startTime instanceof Timestamp) {
      startTime = legacyData.startTime.toDate();
    } else if (legacyData.startTime instanceof Date) {
      startTime = legacyData.startTime;
    } else if (typeof legacyData.startTime === "string") {
      startTime = new Date(legacyData.startTime);
    } else {
      throw new Error(`Invalid startTime type: ${typeof legacyData.startTime}`);
    }

    if (legacyData.endTime instanceof Timestamp) {
      endTime = legacyData.endTime.toDate();
    } else if (legacyData.endTime instanceof Date) {
      endTime = legacyData.endTime;
    } else if (typeof legacyData.endTime === "string") {
      endTime = new Date(legacyData.endTime);
    } else {
      throw new Error(`Invalid endTime type: ${typeof legacyData.endTime}`);
    }

    // Validate that we have valid dates
    if (isNaN(startTime.getTime())) {
      throw new Error(`Invalid startTime date: ${legacyData.startTime}`);
    }
    if (isNaN(endTime.getTime())) {
      throw new Error(`Invalid endTime date: ${legacyData.endTime}`);
    }
  } catch (error) {
    console.error(
      `[!] Date conversion error for event ${legacyData.id}:`,
      error,
    );
    throw error;
  }

  return {
    eventId: legacyData.id || uuidv4(),
    venue,
    isMusicEvent: legacyData.isMusicEvent ?? true, // Default to true if undefined
    url: legacyData.url,
    title: legacyData.title,
    description: legacyData.description,
    performers: legacyData.artists || [], // Ensure array
    ticketPrice: legacyData.ticketPrice ?? null,
    doorPrice: legacyData.doorPrice ?? null, // Handle undefined
    startTime: startTime,
    endTime: endTime,
    flierUrl: legacyData.flierUrl,
    crawlerInfo: {
      timestamp: runTimestamp,
      runId: runId,
      encodedLink: encodedLink,
    },
  };
}

/**
 * Get venue by ID
 */
async function getVenueById(venueId: string): Promise<UserModel | null> {
  try {
    const venueDoc = await usersRef.doc(venueId).get();
    if (!venueDoc.exists) {
      return null;
    }
    return venueDoc.data() as UserModel;
  } catch (error) {
    console.error(`Error getting venue ${venueId}:`, error);
    return null;
  }
}

/**
 * CLI interface
 */
async function main() {
  const dryRun =
    process.argv.includes("--dry-run") || process.argv.includes("-d");
  const force = process.argv.includes("--force") || process.argv.includes("-f");

  if (!dryRun && !force) {
    console.error(
      "This is a destructive operation. Use --dry-run to test or --force to execute.",
    );
    process.exit(1);
  }

  if (FAILED_RUN_IDS.length === 0) {
    console.error(
      "No failed runIds specified. Please update the FAILED_RUN_IDS array with your specific failed runIds.",
    );
    process.exit(1);
  }

  try {
    // First, find which scrapers contain the failed runIds
    const failedRuns = await findFailedRuns(FAILED_RUN_IDS);

    if (failedRuns.length === 0) {
      console.error("No matching runs found for the specified runIds.");
      process.exit(1);
    }

    await migrateSpecificRuns(failedRuns, dryRun);
    console.log("[+] Specific run migration completed successfully!");
  } catch (error) {
    console.error("[!] Migration failed:", error);
    process.exit(1);
  }
}

main().catch(console.error);

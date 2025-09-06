import { Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";
import { db } from "../utils/firebase.js";
import { EventData, Booking, UserModel } from "../types.js";

// Legacy types from webscrapers
interface LegacyScrapedEventData {
  id: string;
  isMusicEvent: boolean | undefined;
  url: string;
  title: string | null;
  description: string | null;
  artists: string[];
  ticketPrice: number | null;
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
  // Additional scraper metadata fields
  name?: string;
  url?: string;
  sitemap?: string;
  venue?: UserModel;
  location?: any;
}

interface LegacyBooking {
  id: string;
  scraperInfo: {
    scraperId: string;
    runId: string;
  };
  serviceId: string | null;
  name: string;
  note: string;
  requesterId: string;
  requesteeId: string;
  status: string;
  rate: number;
  startTime: Timestamp;
  endTime: Timestamp;
  timestamp: Timestamp;
  flierUrl: string | null;
  eventUrl: string | null;
  location: any;
  genres: string[];
}

const crawlerRef = db.collection("crawler");
const rawScrapeDataRef = db.collection("rawScrapeData");
const bookingsRef = db.collection("bookings");
const usersRef = db.collection("users");

// Legacy scraper IDs are imported from configs

/**
 * Main migration function
 */
export async function migrateLegacyScrapers(
  dryRun: boolean = true,
): Promise<void> {
  console.log(`[+] Starting legacy scraper migration (dry run: ${dryRun})`);

  let totalEvents = 0;
  let totalBookings = 0;
  let errors = 0;

  try {
    // Get all legacy scraper documents
    const scraperDocs = await rawScrapeDataRef.get();

    for (const scraperDoc of scraperDocs.docs) {
      const scraperId = scraperDoc.id;
      // const scraperData = scraperDoc.data();

      console.log(`[+] Processing scraper: ${scraperId}`);

      // Get the venue information
      const venue = await getVenueById(scraperId);
      if (!venue) {
        console.error(`[!] No venue found for scraper ID: ${scraperId}`);
        continue;
      }

      // Get all scrape runs for this scraper
      const runsSnapshot = await rawScrapeDataRef
        .doc(scraperId)
        .collection("scrapeRuns")
        .get();

      for (const runDoc of runsSnapshot.docs) {
        const runId = runDoc.id;
        const runData = runDoc.data() as LegacyRunData;

        console.log(`[+] Processing run: ${runId} for scraper: ${scraperId}`);

        // Get all scrape results for this run
        const resultsSnapshot = await rawScrapeDataRef
          .doc(scraperId)
          .collection("scrapeRuns")
          .doc(runId)
          .collection("scrapeResults")
          .get();

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
              console.log(
                `[DRY RUN] Would migrate event: ${newEventData.title}`,
              );
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
                  startTime: resultDoc.data().startTime,
                  endTime: resultDoc.data().endTime,
                  title: resultDoc.data().title,
                },
                null,
                2,
              ),
            );
            errors++;
          }
        }
      }

      // Migrate bookings for this scraper
      const migratedBookingCount = await migrateBookingsForScraper(
        scraperId,
        dryRun,
      );
      totalBookings += migratedBookingCount;
    }

    console.log("[+] Migration complete!");
    console.log(`    - Total events: ${totalEvents}`);
    console.log(`    - Total bookings updated: ${totalBookings}`);
    console.log(`    - Errors: ${errors}`);
  } catch (error) {
    console.error("[!] Migration failed:", error);
    throw error;
  }
}

/**
 * Transform legacy event data to new schema
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
    isMusicEvent: legacyData.isMusicEvent ?? true,
    url: legacyData.url,
    title: legacyData.title,
    description: legacyData.description,
    performers: legacyData.artists, // artists -> performers
    ticketPrice: legacyData.ticketPrice,
    doorPrice: legacyData.doorPrice ?? null,
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
 * Migrate bookings to add crawlerInfo
 */
async function migrateBookingsForScraper(
  scraperId: string,
  dryRun: boolean,
): Promise<number> {
  console.log(`[+] Migrating bookings for scraper: ${scraperId}`);

  const bookingsSnapshot = await bookingsRef
    .where("scraperInfo.scraperId", "==", scraperId)
    .get();

  let count = 0;

  for (const bookingDoc of bookingsSnapshot.docs) {
    const booking = bookingDoc.data() as LegacyBooking;

    // Create crawlerInfo from scraperInfo
    const crawlerInfo = {
      timestamp: booking.timestamp.toDate(),
      runId: booking.scraperInfo.runId,
      encodedLink: booking.eventUrl ? encodeURIComponent(booking.eventUrl) : "",
    };

    // Find the reference event ID from crawler collection
    let referenceEventId: string | null = null;
    if (booking.eventUrl) {
      const encodedLink = encodeURIComponent(booking.eventUrl);
      const eventDoc = await crawlerRef.doc(encodedLink).get();
      if (eventDoc.exists) {
        const eventData = eventDoc.data();
        referenceEventId = eventData?.eventId || null;
      }
    }

    const updatedBooking: Partial<Booking> = {
      crawlerInfo,
      referenceEventId,
      // Keep scraperInfo for backward compatibility
      scraperInfo: booking.scraperInfo,
    };

    if (!dryRun) {
      await bookingsRef.doc(booking.id).set(updatedBooking, { merge: true });
      console.log(`[+] Updated booking: ${booking.name}`);
    } else {
      console.log(`[DRY RUN] Would update booking: ${booking.name}`);
    }

    count++;
  }

  return count;
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

  try {
    await migrateLegacyScrapers(dryRun);
    console.log("[+] Migration completed successfully!");
  } catch (error) {
    console.error("[!] Migration failed:", error);
    process.exit(1);
  }
}

main().catch(console.error);

import type { Browser } from "puppeteer";
import puppeteer from "puppeteer";
import Sitemapper from "sitemapper";
import { config } from "./config";
import { ScrapedEventData } from "../../types";
import { v4 as uuidv4 } from "uuid";
import { endScrapeRun, saveScrapeResult } from "../../utils/database";
import {
  notifyOnScrapeFailure,
  notifyOnScrapeSuccess,
} from "../../utils/notifications";
import { configDotenv } from "dotenv";
import { getArtists, getDate, getEventNameFromUrl, getTime } from "./parsing";
import { initScrape } from "../../utils/startup";

async function scrapeEvent(
  browser: Browser,
  url: string,
): Promise<ScrapedEventData | null> {
  const page = await browser.newPage();
  await page.goto(url);

  const suffix = getEventNameFromUrl(url);
  if (suffix === null) {
    console.log("[-] failed to get event name from url");
    return null;
  }

  const eventArtists: string[] = await getArtists(page);
  const eventDate: string[] = await getDate(page);
  const eventTime: string[] = await getTime(page);

  // Combine date and time and convert to Date object
  const combinedDate: string = eventDate.join(" ");
  const combinedTime: string = eventTime[0];
  const dateTimeString: string = `${combinedDate} ${combinedTime}`;
  const dateTime: Date = new Date(dateTimeString);

  const id = uuidv4();

  return {
    id,
    url,
    isMusicEvent: true,
    title: eventArtists.join(", "),
    description: "",
    ticketPrice: null,
    doorPrice: null,
    artists: eventArtists,
    startTime: dateTime,
    endTime: dateTime,
    flierUrl: null,
  };
}

export async function scrape({ online }: { online: boolean }): Promise<void> {
  console.log(`[+] scraping [online: ${online}]`);
  const { latestRun, runId, metadata } = await initScrape({ online, config });

  try {
    const lateRunStart = latestRun?.startTime ?? null;
    const lastmod = lateRunStart?.getTime();
    const sitemap = new Sitemapper({
      url: metadata.sitemap,
      lastmod,
      // lastmod: (new Date('2024-02-01')).getTime(),
      timeout: 30000,
    });

    const { sites } = await sitemap.fetch();

    console.log("[+] urls:", sites.length);

    // Launch the browser and open a new blank page
    const browser = await puppeteer.launch({
      headless: "new",
    });

    for (const url of sites) {
      try {
        const data = await scrapeEvent(browser, url);
        if (data === null) {
          console.log("[-] failed to scrape data");
          continue;
        }

        if (online) {
          await saveScrapeResult(metadata, runId, data);
        }
      } catch (e) {
        console.log("[!!!] error:", e);
        continue;
      }
    }
    await browser.close();

    if (online) {
      await endScrapeRun(metadata, runId, { error: null });
      await notifyOnScrapeSuccess({
        runId,
        eventCount: sites.length,
      });
    }
  } catch (err: any) {
    console.log("[-] error:", err);
    await endScrapeRun(metadata, runId, { error: err.message });
    if (online) {
      await notifyOnScrapeFailure({
        error: err.message,
      });
    }
    throw err;
  }
}

if (require.main === module) {
  configDotenv({
    path: ".env",
  });

  scrape({ online: false });
}

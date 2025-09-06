import puppeteer, { type Browser } from "puppeteer";
import Sitemapper from "sitemapper";
import { ScrapedEventData } from "../../types";
import { endScrapeRun, saveScrapeResult } from "../../utils/database";
import { config } from "./config";
import {
  notifyOnScrapeFailure,
  notifyOnScrapeSuccess,
} from "../../utils/notifications";
import {
  getEventNameFromUrl,
  getTitle,
  getDescription,
  getArtists,
  getTimes,
  getFlierUrl,
} from "./parsing";
import { configDotenv } from "dotenv";
import { v4 as uuidv4 } from "uuid";
import { initScrape } from "../../utils/startup";

async function scrapeEvent(
  browser: Browser,
  eventUrl: string,
): Promise<ScrapedEventData | null> {
  const eventName = getEventNameFromUrl(eventUrl);

  if (!eventName) {
    console.log("[-] event name not found: ", eventUrl);
    return null;
  }

  console.log("[+] scraping event:", eventName);

  const page = await browser.newPage();

  // Navigate the page to a URL
  await page.goto(eventUrl);

  // Set screen size
  await page.setViewport({ width: 1080, height: 1024 });

  const title = (await getTitle(page)) ?? "";

  const description = (await getDescription(page)) ?? "";

  const eventTimes = await getTimes(page);
  if (!eventTimes) {
    console.log("[-] start date not found");
    return null;
  }

  const { startTime, endTime } = eventTimes;

  const artists = await getArtists(title, description);

  const flierUrl = await getFlierUrl(page);

  const id = uuidv4();

  return {
    id,
    isMusicEvent: true,
    url: eventUrl,
    title,
    description,
    ticketPrice: null,
    doorPrice: null,
    artists,
    startTime,
    endTime,
    flierUrl,
  };
}

export async function scrape({ online }: { online: boolean }): Promise<void> {
  console.log(`[+] scraping ember music hall [online: ${online}]`);
  const { runId, latestRun, metadata } = await initScrape({ online, config });

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

    console.log("[+] ember music hall urls:", sites.length);

    // Launch the browser and open a new blank page
    const browser = await puppeteer.launch({
      headless: "new",
    });

    for (const emberUrl of sites) {
      try {
        const data = await scrapeEvent(browser, emberUrl);
        if (data === null) {
          console.log("[-] failed to scrape data");
          continue;
        }

        console.log({ data });

        // console.log(`[+] scraped data: ${data.title} - #${data.artists.join('|')}# [${data.startTime.toLocaleString()} - ${data.endTime.toLocaleString()}]`);
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
    if (online) {
      await endScrapeRun(metadata, runId, { error: null });
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

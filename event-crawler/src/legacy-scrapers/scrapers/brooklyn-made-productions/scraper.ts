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
import { initScrape } from "../../utils/startup";
import { getEventDetails, getEventNameFromUrl, getFlierUrl } from "./parsing";

async function scrapeEvent(
  browser: Browser,
  url: string,
): Promise<ScrapedEventData | null> {
  const eventName = getEventNameFromUrl(url);

  if (!eventName) {
    console.log("[-] event name not found: ", url);
    return null;
  }

  console.log("[+] scraping event:", eventName);
  const page = await browser.newPage();
  await page.goto(url);

  const {
    title,
    description,
    artists,
    startTime,
    endTime,
    doorPrice,
    ticketPrice,
  } = await getEventDetails(page);

  const flierUrl = await getFlierUrl(page);
  const id = uuidv4();
  return {
    id,
    url,
    isMusicEvent: true,
    title,
    description,
    ticketPrice,
    doorPrice,
    artists,
    startTime: startTime ?? new Date(),
    endTime: endTime ?? new Date(),
    flierUrl,
  };
}

export async function scrape({ online }: { online: boolean }): Promise<void> {
  console.log(`[+] scraping [online: ${online}]`);
  const { latestRun, runId, metadata } = await initScrape({ online, config });

  try {
    const lateRunStart = latestRun?.startTime ?? null;
    const lastmod = lateRunStart?.getTime();
    const sitemap = new Sitemapper({
      url: config.sitemap,
      lastmod,
      timeout: 30000,
    });

    const { sites } = await sitemap.fetch();

    console.log("[+] urls:", sites.length);

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

        console.log(
          `[+] \n-url: ${url}\n- title: ${data.title}\n - performers: ${data.artists.join(",")}\n- ticket price: (${data.doorPrice}, ${data.ticketPrice})\n- times: [${data.startTime.toLocaleString()} - ${data.endTime.toLocaleString()}]\n- ${data.flierUrl}`,
        );

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

  scrape({ online: true });
}

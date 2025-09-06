import puppeteer, { type Browser } from "puppeteer";
import Sitemapper from "sitemapper";
import { ScrapedEventData } from "../../types";
import { endScrapeRun, saveScrapeResult } from "../../utils/database";
import {
  notifyOnScrapeFailure,
  notifyOnScrapeSuccess,
  notifyScapeStart,
} from "../../utils/notifications";
import {
  getEventNameFromUrl,
  parseArtists,
  parseTicketPrice,
  parseDescription,
  parseDates,
  getFlierUrl,
} from "./parsing";
import { config } from "./config";
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
  await page.goto(eventUrl);
  await page.setViewport({ width: 1080, height: 1024 });

  const element = await page.waitForSelector(".wpem-heading-text");

  if (!element) {
    console.log("[-] element not found");
    return null;
  }

  const title = (
    (await page.evaluate((element) => element.textContent, element)) ?? ""
  ).trim();
  const description = (await parseDescription(page)) ?? "";

  // null if price string is empty
  const priceContainer = await page.waitForSelector(".wpem-event-details");

  if (!priceContainer) {
    console.log("[-] price not found");
    return null;
  }

  const priceText = (
    (await page.evaluate(
      (priceContainer) => priceContainer.textContent,
      priceContainer,
    )) ?? ""
  ).trim();

  const [ticketPrice, doorPrice] = parseTicketPrice(priceText);
  const { startTime, endTime } = await parseDates(page);

  const artists = await parseArtists(title, description);
  const flierUrl = await getFlierUrl(page);

  const id = uuidv4();

  return {
    id,
    url: eventUrl,
    isMusicEvent: true,
    title,
    description,
    ticketPrice: ticketPrice ?? null,
    doorPrice: doorPrice ? doorPrice : ticketPrice ?? null,
    artists,
    startTime,
    endTime,
    flierUrl,
  };
}

export async function scrape({ online }: { online: boolean }): Promise<void> {
  console.log(`[+] scraping [online: ${online}]`);
  const { latestRun, runId, metadata } = await initScrape({ config, online });

  try {
    const lateRunStart = latestRun?.startTime ?? null;
    const lastmod = lateRunStart?.getTime();
    console.log(`[+] last mode is ${lastmod}`);
    const sitemap = new Sitemapper({
      url: metadata.sitemap,
      lastmod,
      // lastmod: new Date("2022-12-16").getTime(),
      timeout: 30000,
    });

    const { sites } = await sitemap.fetch();

    console.log("[+] urls:", sites.length);
    await notifyScapeStart({
      runId,
      eventCount: sites.length,
    });

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

        console.log(
          `[+] \n- ${data.title}\n - ${data.artists.join(",")}\n - [${data.startTime.toLocaleString()} - ${data.endTime.toLocaleString()}]\n- ${data.flierUrl}`,
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

  scrape({ online: false });
}

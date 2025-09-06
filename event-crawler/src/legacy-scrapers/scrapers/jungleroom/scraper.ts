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
  parseTimes,
} from "./parsing";
import { config } from "./config";
import { configDotenv } from "dotenv";
import { v4 as uuidv4 } from "uuid";
import { getTextContent } from "../../utils/text_content";
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
  // page.on('console', async (msg) => {
  //     const msgArgs = msg.args();
  //     for (let i = 0; i < msgArgs.length; ++i) {
  //         const val = await msgArgs[i].jsonValue();
  //         console.log(`[PAGE] ${val}`);
  //     }
  // });

  // Navigate the page to a URL
  await page.goto(eventUrl);

  // Set screen size
  await page.setViewport({ width: 1080, height: 1024 });

  const element = await page.waitForSelector(".eventitem-title");

  if (!element) {
    console.log("[-] element not found");
    return null;
  }

  const title = (
    (await page.evaluate((element) => element.textContent, element)) ?? ""
  ).trim();

  // Use evaluate to capture text content
  const description = await getTextContent(page, ".eventitem-column-content");

  const ticketPrice = parseTicketPrice(description) ?? 5;

  const { startTimeStr, endTimeStr } = await page.evaluate(() => {
    function getTextContent(element: Element | ChildNode) {
      let text = "";

      // Iterate over child nodes
      element.childNodes.forEach((node) => {
        if (node.nodeType === Node.TEXT_NODE) {
          text += ` ${node.textContent} `;
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          text += ` ${getTextContent(node)} `;
        }
      });

      return text;
    }

    const container = document.querySelector(".eventitem-meta-date");
    if (container === null) {
      console.log("[-] container not found");
      return {
        startTime: null,
        endTime: null,
      };
    }

    const dateString = getTextContent(container).trim();

    // Define a regex pattern to capture date and time components
    const regexPattern =
      /\s*(\w+), (\w+) (\d{1,2}), (\d{4})\s*(\d{1,2}:\d{2} (AM|PM))\s*/g;

    // Create an array to store matched groups
    let match;
    const matches = [];

    // Iterate over matches using the regex pattern
    while ((match = regexPattern.exec(dateString)) !== null) {
      matches.push(match.slice(1));
    }

    return {
      startTimeStr: matches[0] ?? null,
      endTimeStr: matches[1] ?? null,
    };
  });

  if (!startTimeStr || !endTimeStr) {
    console.log("[-] start or end time not found");
    return null;
  }

  const { startTime, endTime } = parseTimes(startTimeStr, endTimeStr);

  if (!startTime || !endTime) {
    console.log(`[-] start or end time not found [${startTime}, ${endTime}]`);
    return null;
  }

  const artists = await parseArtists(title);

  const id = uuidv4();

  return {
    id,
    isMusicEvent: true,
    url: eventUrl,
    title,
    description,
    ticketPrice,
    doorPrice: ticketPrice,
    artists,
    startTime,
    endTime,
    flierUrl: null,
  };
}

export async function scrape({ online }: { online: boolean }): Promise<void> {
  console.log(`[+] scraping [online: ${online}]`);
  const { latestRun, runId, metadata } = await initScrape({ config, online });

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
    await notifyScapeStart({
      runId,
      eventCount: sites.length,
    });

    // Launch the browser and open a new blank page
    const browser = await puppeteer.launch({
      headless: "new",
    });

    for (const jungleRoomUrl of sites) {
      try {
        const data = await scrapeEvent(browser, jungleRoomUrl);
        if (data === null) {
          console.log("[-] failed to scrape data");
          continue;
        }

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

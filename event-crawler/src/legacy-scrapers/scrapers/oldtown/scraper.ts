import puppeteer, { type Browser } from "puppeteer";
import Sitemapper from "sitemapper";
import { ScrapedEventData } from "../../types";
import { endScrapeRun, saveScrapeResult } from "../../utils/database";
import { config } from "./config";
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
  parseTimes,
  parseFlierUrl,
} from "./parsing";
import { v4 as uuidv4 } from "uuid";
import { configDotenv } from "dotenv";
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

  const element = await page.waitForSelector(".headings > h5");

  if (!element) {
    console.log("[-] element not found");
    return null;
  }

  const title = (
    (await page.evaluate((element) => element.textContent, element)) ?? ""
  ).trim();
  const description = (await parseDescription(page)) ?? "";

  // null if price string is empty
  const [ticketPrice, doorPrice] = parseTicketPrice(description);

  const timeRegexPattern = /\b(\d{1,2}(?::\d{2})?)(?:a|p|am|pm)?\b/gm;

  const dateRegexPattern =
    /(\b\d{1,2}\b\s+\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b)/gm;

  // Create an array to store matched groups
  let match;
  const timeMatches: string[] = [];
  const dateMatches: string[] = [];
  const descriptionParts = description.split("\n");
  const monthRegex = /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/;
  const timePRegex = /\b\d+p\b/gm;
  let timeParts = "";
  let dateParts = "";
  descriptionParts.forEach((string) => {
    if (
      string.includes("pm") ||
      string.includes("am ") ||
      string.includes("Doors") ||
      string.includes("doors") ||
      (string.includes(":") && string.includes("-"))
    ) {
      timeParts += string;
      if (timePRegex.test(string)) {
        timeParts += string;
      }
    }
    if (monthRegex.test(string)) {
      dateParts += string;
    }
  });

  // Iterate over matches using the regex pattern
  while ((match = timeRegexPattern.exec(timeParts)) !== null) {
    timeMatches.push(match[1]);
  }
  while ((match = dateRegexPattern.exec(dateParts)) !== null) {
    dateMatches.push(match[1]);
  }

  const filteredTimeMatches = timeMatches.filter((match) => {
    const index = description.indexOf(match);
    if (index > 0) {
      const prevChar = description.charAt(index - 1);
      const nextChar = description.charAt(index + 1);
      return nextChar !== "+" && prevChar !== "$" && match !== "21";
    }
    return true;
  });

  const month = dateMatches[0];
  const splitMonth = month.split(/\s+/);

  const startTimeList = [];
  const endTimeList = [];
  const currDate = new Date();
  const year = String(currDate.getFullYear());
  if (filteredTimeMatches && dateMatches) {
    const monthString = String(splitMonth[1]);
    const dayString = String(splitMonth[0]);
    startTimeList.push(monthString);
    startTimeList.push(dayString);

    startTimeList.push(year);
    endTimeList.push(monthString);
    endTimeList.push(dayString);
    endTimeList.push(year);
    if (timeMatches[0]) {
      const timeMatchesLength = filteredTimeMatches.length;
      let showTimeString;
      let endTimeString;
      if (timeMatchesLength > 2) {
        showTimeString = String(filteredTimeMatches[0]);
        const showTimeValue = Number(showTimeString.split(":")[0]);
        const lastTime = Number(
          filteredTimeMatches[timeMatchesLength - 1].split(":")[0],
        );
        const endTime =
          lastTime < showTimeValue
            ? filteredTimeMatches[timeMatchesLength - 2]
            : filteredTimeMatches[timeMatchesLength - 1];

        if (endTime.includes(":")) {
          endTimeString = String(endTime) + "PM";
        } else {
          endTimeString = String(lastTime) + ":00PM";
        }
      } else {
        showTimeString = String(filteredTimeMatches[1]);

        endTimeString = String(Number(showTimeString.split(":")[0]) + 2);
        if (endTimeString.includes(":")) {
          endTimeString = String(endTimeString) + "PM";
        } else {
          endTimeString = String(endTimeString) + ":00PM";
        }

        //const doorTimeString = String(filteredTimeMatches[0]);
      }
      startTimeList.push(showTimeString + ":00PM");
      endTimeList.push(endTimeString);
    }
  }

  const startTimeStr = startTimeList;
  const endTimeStr = endTimeList;

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
  const flierUrl = await parseFlierUrl(page);

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
  console.log(`[+] scraping old town [online: ${online}]`);
  const { latestRun, runId, metadata } = await initScrape({ config, online });
  try {
    const lateRunStart = latestRun?.startTime ?? null;
    const lastmod = lateRunStart?.getTime();
    console.log(lastmod);

    const sitemap = new Sitemapper({
      url: metadata.sitemap,

      timeout: 30000,
    });

    const { sites } = await sitemap.fetch();

    console.log("[+] old town urls:", sites.length);
    await notifyScapeStart({
      runId,
      eventCount: sites.length,
    });

    // Launch the browser and open a new blank page
    const browser = await puppeteer.launch({
      headless: "new",
    });

    for (const oldTownUrl of sites) {
      try {
        const data = await scrapeEvent(browser, oldTownUrl);
        if (data === null) {
          console.log("[-] failed to scrape data");
          continue;
        }

        console.log(
          `[+] \n- ${data.title}\n - ${data.artists.join(",")}\n- ${data.ticketPrice}\n- [${data.startTime.toLocaleString()} - ${data.endTime.toLocaleString()}]\n- ${data.flierUrl}`,
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
    if (online) {
      await endScrapeRun(metadata, runId, { error: err.message });
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

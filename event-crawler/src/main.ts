/* eslint-disable indent */
import { CheerioCrawler, Sitemap } from "crawlee";
import { configDotenv } from "dotenv";
import { v4 as uuidv4 } from "uuid";
import { getRouter } from "./routes.js";
import { EventData } from "./types.js";
import {
  buildDomainMap,
  getAllScrapedLinks,
  getUserByUsername,
  getVenueUsernameChunk,
  saveEventData,
  setBestDaysOfWeek,
  setVenueTopPerformers,
} from "./utils/database.js";
import { getBaseDomain } from "./utils/parsing.js";
configDotenv({
  path: ".env.local",
});

const DRY_RUN = false;
const blacklistDomains = [
  ".edu",
  "facebook.com",
  "instagram.com",
  "www.instagram.com",
  "www.facebook.com",
  "yelp.com",
  "www.yelp.com",
  "linktr.ee",
  "toast.site",
  "www.toast.site",
  "google.com",
  "www.google.com",
];

async function main({ dryRun }: { dryRun?: boolean }) {
  const runId = uuidv4();
  const initVenueUsernames = getVenueUsernameChunk();
  const domainMap = await buildDomainMap(initVenueUsernames);
  const simplifiedDomainMap = Object.fromEntries(
    Object.entries(domainMap).map(([domain, { venue }]) => [
      domain,
      venue.username,
    ]),
  );
  console.log({ domainMap: simplifiedDomainMap });

  const venueIds = Object.values(domainMap).map(({ venue }) => venue.id);
  const finishedLinks = await getAllScrapedLinks(venueIds);
  const router = await getRouter(finishedLinks);
  const crawler = new CheerioCrawler({
    // proxyConfiguration: new ProxyConfiguration({ proxyUrls: ['...'] }),
    requestHandler: router,
    preNavigationHooks: [
      async () => {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      },
    ],
    //   minConcurrency: 1,
    maxConcurrency: 50,
    // comment this option to scrape the full website.
    // maxRequestsPerCrawl: 20,
  });

  const startUrls = Object.values(domainMap).map(({ url }) => url);
  for (const url of startUrls) {
    const uri = new URL(url);
    const domain = uri.hostname;
    if (blacklistDomains.some((domain) => url.includes(domain))) {
      continue;
    }
    const sitemapUrl = `https://${domain}/sitemap.xml`;
    console.log("[+] loading sitemap", sitemapUrl);
    const { urls } = await Sitemap.load(sitemapUrl);

    const filteredUrls = urls.filter((url) => {
      const excludedPaths = ["/photobooth", "www.arrobanat.com", "format=ical"];

      return !excludedPaths.some((path) => url.includes(path));
    });

    await crawler.addRequests(filteredUrls);
  }

  await crawler.run(startUrls);

  const data = await crawler.getData();
  const items = data.items;
  for (const [index, item] of items.entries()) {
    // ### WARNING!!!
    // EventData was serialized to JSON and deserialized back to a JS object.
    // This means that the Date objects are now strings.
    const { loadedUrl, ...rest } = item as Omit<
      EventData,
      "venue" | "crawlerInfo"
    > & { loadedUrl: string };
    const domainName = getBaseDomain(loadedUrl);
    const venuePair = domainMap[domainName];
    const venue = venuePair?.venue ?? null;
    if (venue === null) {
      console.error(`[!] no venue found for ${domainName}`);
      continue;
    }

    if (dryRun) {
      console.log(`[${index}] dry run, would save event data for ${loadedUrl}`);
      continue;
    }

    if (loadedUrl.includes("/list/")) {
      console.log("[!] skipping... list page", { url: loadedUrl });
      continue;
    }

    const encodedLink = encodeURIComponent(loadedUrl);
    try {
      await saveEventData(encodedLink, {
        ...rest,
        eventId: uuidv4(),
        url: rest.url ?? loadedUrl,
        venue,
        crawlerInfo: {
          runId,
          timestamp: new Date(),
          encodedLink,
        },
      });

      console.log(`[${index}] save event data for ${loadedUrl}`);
    } catch (error) {
      console.error("[!] error saving event data for", loadedUrl, error);
    }
  }

  for (const username of initVenueUsernames) {
    if (dryRun) {
      continue;
    }

    const venue = await getUserByUsername(username);
    if (!venue) {
      console.error(`[!] no venue found for ${username}`);
      continue;
    }

    await setBestDaysOfWeek(venue.id);

    await setVenueTopPerformers({
      venueId: venue.id,
      count: 5,
    });
  }

  console.log(
    `[+] set best days of the week and top performers for ${initVenueUsernames} venues`,
  );

  return;
}

main({ dryRun: DRY_RUN })
  .then(() => console.log("done"))
  .catch(console.error);

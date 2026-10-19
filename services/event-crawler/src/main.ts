import { createHash } from "node:crypto";
import {
  captureObservations,
  database,
  deliveryKey,
  endRun,
  r2EvidenceStore,
  startRun,
  withFormattingV2,
} from "@tapped/postgres-ingestion";
import { CheerioCrawler, Sitemap } from "crawlee";
import { configDotenv } from "dotenv";
import { getRouter } from "./routes.js";
import { buildDomainMap, getVenueUsernameChunk, hasLinkBeenScraped } from "./utils/database.js";
import { getBaseDomain } from "./utils/parsing.js";

configDotenv({ path: ".env.local" });
const SOURCE = "event-crawler";
const PARSER = "event-crawler-extract-v1";
const blacklistDomains = [".edu", "facebook.com", "instagram.com", "yelp.com", "linktr.ee", "toast.site", "google.com"];

async function main() {
  // Fail closed before any fetching when restricted database/private evidence configuration is absent.
  const pool = database();
  const store = r2EvidenceStore();
  const domainMap = await buildDomainMap(getVenueUsernameChunk());
  const runId = await startRun(SOURCE, SOURCE, PARSER);
  let failed = 0;
  try {
    const router = await getRouter(hasLinkBeenScraped, async (data, body, observedAt) => {
      const loadedUrl = String(data.loadedUrl);
      const venueId = domainMap[getBaseDomain(loadedUrl)]?.venue.id ?? null;
      const sourceKey = encodeURIComponent(loadedUrl);
      const hash = createHash("sha256").update(body).update(JSON.stringify(data)).digest("hex");
      await captureObservations(
        pool,
        store,
        [
          withFormattingV2(
            {
              source: SOURCE,
              sourceKey,
              deliveryKey: deliveryKey(SOURCE, runId, sourceKey, hash),
              observedAt,
              parserVersion: PARSER,
              venueId,
              runId,
              data,
            },
            "usd_major",
          ),
        ],
        Buffer.from(
          JSON.stringify({ url: loadedUrl, observedAt, responseBase64: body.toString("base64"), extraction: data }),
        ),
        {
          retention: "evidence",
          contentType: "application/json",
        },
      );
    });
    const crawler = new CheerioCrawler({
      requestHandler: router,
      // The database pool is bounded independently of fetch concurrency. Per-domain throttling
      // prevents one host being hammered as more targets/workers are introduced.
      maxConcurrency: 10,
      sameDomainDelaySecs: 1,
      maxRequestRetries: 2,
      failedRequestHandler: async () => {
        failed++;
      },
    });
    const urls = Object.values(domainMap)
      .map(({ url }) => url)
      .filter((url) => !blacklistDomains.some((domain) => url.includes(domain)));
    for (const url of urls) {
      const { urls: sitemapUrls } = await Sitemap.load(`https://${new URL(url).hostname}/sitemap.xml`);
      await crawler.addRequests(
        sitemapUrls.filter((link) => !link.includes("/photobooth") && !link.includes("format=ical")),
      );
    }
    // Each response is archived and recorded inside its handler; no whole-run dataset in RAM,
    // deferred persistence, public venue snapshots, or application booking/profile writes.
    await crawler.run(urls);
    await endRun(runId, failed ? `${failed} requests failed` : null);
    if (failed) throw new Error("Some crawler requests failed");
  } catch {
    await endRun(runId, "Crawler execution failed; inspect restricted diagnostics");
    throw new Error("Crawler execution failed");
  } finally {
    await pool.end();
  }
}
main().catch(() => {
  console.error("Event crawler failed");
  process.exitCode = 1;
});

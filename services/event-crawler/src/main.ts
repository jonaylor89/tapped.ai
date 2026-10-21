import { createHash } from "node:crypto";
import {
  captureObservations,
  database,
  deliveryKey,
  endRun,
  knownVenueRoutes,
  r2EvidenceStore,
  requireUnambiguousVenueRoutes,
  resolveVenueRouting,
  startRun,
  venueRoutesForSeeds,
  withFormattingV2,
} from "@tapped/postgres-ingestion";
import { CheerioCrawler, Sitemap } from "crawlee";
import { configDotenv } from "dotenv";
import { getRouter } from "./routes.js";
import { buildVenueRoutes, getVenueUsernameChunk, hasLinkBeenScraped } from "./utils/database.js";

configDotenv({ path: ".env.local" });
const SOURCE = "event-crawler";
const PARSER = "event-crawler-extract-v2-scoped-routing";
const blacklistDomains = [".edu", "facebook.com", "instagram.com", "yelp.com", "linktr.ee", "toast.site", "google.com"];

async function main() {
  // Fail closed before any fetching when restricted database/private evidence configuration is absent.
  const pool = database();
  const store = r2EvidenceStore();
  const selectedRoutes = await buildVenueRoutes(getVenueUsernameChunk());
  // A shared brand can be ambiguous even if only one of its venues is selected in this chunk.
  const venueRoutes = venueRoutesForSeeds(await knownVenueRoutes(), selectedRoutes);
  // Do not fetch a whole ambiguous batch and silently assign the last profile on a shared domain.
  requireUnambiguousVenueRoutes(venueRoutes);
  const runId = await startRun(SOURCE, SOURCE, PARSER);
  let failed = 0;
  try {
    const router = await getRouter(hasLinkBeenScraped, async (data, body, observedAt, context) => {
      const loadedUrl = context.loadedUrl;
      const routing = resolveVenueRouting(venueRoutes, context);
      const sourceKey = encodeURIComponent(loadedUrl);
      const extraction = { ...data, venueRouting: routing, discoveryContext: context };
      const hash = createHash("sha256").update(body).update(JSON.stringify(extraction)).digest("hex");
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
              venueId: routing.venueId,
              venueRoutingStatus: routing.status,
              runId,
              data,
            },
            "usd_major",
          ),
        ],
        Buffer.from(
          JSON.stringify({ url: loadedUrl, observedAt, responseBase64: body.toString("base64"), extraction }),
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
    const seeds = selectedRoutes.filter(({ url }) => !blacklistDomains.some((domain) => url.includes(domain)));
    const requests = seeds.map(({ url, venueId }) => ({
      url,
      userData: { discoveryVenueId: venueId, discoveryUrl: url },
    }));
    for (const { url, venueId } of seeds) {
      const { urls: sitemapUrls } = await Sitemap.load(new URL("/sitemap.xml", url).href);
      await crawler.addRequests(
        sitemapUrls
          .filter(
            (link) =>
              !link.includes("/photobooth") &&
              !link.includes("format=ical") &&
              resolveVenueRouting(venueRoutes, {
                requestedUrl: link,
                loadedUrl: link,
                discoveryVenueId: venueId,
                discoveryUrl: url,
              }).status === "resolved",
          )
          .map((link) => ({ url: link, userData: { discoveryVenueId: venueId, discoveryUrl: url } })),
      );
    }
    // Each response is archived and recorded inside its handler; no whole-run dataset in RAM,
    // deferred persistence, public venue snapshots, or application booking/profile writes.
    await crawler.run(requests);
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

import type {
  Option,
  Location,
  RunData,
  ScraperConfig,
  ScraperMetadata,
} from "../types";
import { getUserById, startScrapeRun, getLatestRun } from "./database";
import { searchPlaces } from "./place";

export async function initScrape({
  config,
  online,
}: {
  config: ScraperConfig;
  online: boolean;
}): Promise<{
  runId: string;
  latestRun: Option<RunData>;
  metadata: ScraperMetadata;
}> {
  const venue = await getUserById(config.id);
  if (venue === null) {
    throw new Error("venue not found");
  }

  const places = await searchPlaces(config.city);
  if (places.length === 0) {
    throw new Error("no places found");
  }

  const place = places[0];
  const location: Location = {
    placeId: place.id,
    geohash: place.geohash,
    lat: place.latitude,
    lng: place.longitude,
  };

  const metadata: ScraperMetadata = {
    id: config.id,
    name: config.name,
    url: config.url,
    sitemap: config.sitemap,
    location,
    venue,
  };

  const latestRun = await getLatestRun(config.id);
  const runId = online ? await startScrapeRun(metadata) : "test-run";

  return {
    runId,
    latestRun,
    metadata,
  };
}

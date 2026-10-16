import { endRun, latestRun, profile, saveRunEvent, startRun } from "@tapped/postgres-ingestion";
import type { Option, RunData, ScrapedEventData, ScraperMetadata, UserModel } from "../types";

export async function getUserById(id: string): Promise<Option<UserModel>> {
  return profile<UserModel>(id);
}
export async function startScrapeRun(scraper: ScraperMetadata): Promise<string> {
  return startRun(scraper.venue.id);
}
export async function endScrapeRun(
  _scraper: ScraperMetadata,
  runId: string,
  { error }: { error: string | null },
): Promise<void> {
  await endRun(runId, error);
}
export async function getLatestRun(id: string): Promise<RunData | null> {
  return latestRun(id);
}
export async function saveScrapeResult(scraper: ScraperMetadata, runId: string, data: ScrapedEventData): Promise<void> {
  const key = encodeURIComponent(data.url || `${scraper.venue.id}:${data.startTime.toISOString()}:${data.title}`);
  await saveRunEvent("legacy-scrapers", runId, key, scraper.venue.id, { ...data, performers: data.artists, runId });
}
export async function createBookingsFromEvent(
  scraper: ScraperMetadata,
  runId: string,
  data: ScrapedEventData,
): Promise<void> {
  await saveScrapeResult(scraper, runId, data);
}

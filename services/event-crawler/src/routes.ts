import { isScopedDiscoveryLink, type VenueDiscoveryContext } from "@tapped/postgres-ingestion";
import { createCheerioRouter } from "crawlee";
import { extractEventDataFromPage } from "./utils/openai.js";
import { containsEventPath } from "./utils/parsing.js";

const MAX_PAGE_CONTENT_LENGTH = 15_000;
const MAX_PATH_PARTS = 10;

export async function getRouter(
  shouldSkip: (key: string) => Promise<boolean>,
  capture: (
    data: Record<string, unknown>,
    body: Buffer,
    observedAt: string,
    context: VenueDiscoveryContext,
  ) => Promise<void>,
) {
  const router = createCheerioRouter();
  router.addDefaultHandler(async ({ request, $, body, enqueueLinks, log }) => {
    log.info(request.url);

    if (!request.loadedUrl) {
      return;
    }
    const urlObj = new URL(request.loadedUrl);
    const path = urlObj.pathname;
    const context: VenueDiscoveryContext = {
      requestedUrl: request.url,
      loadedUrl: request.loadedUrl,
      discoveryVenueId:
        typeof request.userData.discoveryVenueId === "string" ? request.userData.discoveryVenueId : undefined,
      discoveryUrl: typeof request.userData.discoveryUrl === "string" ? request.userData.discoveryUrl : undefined,
    };

    try {
      const isRSSFeed = request.loadedUrl.endsWith(".rss");
      const isCalendar = request.loadedUrl.includes("ical=1") || request.loadedUrl.includes("format=ical");
      if (isRSSFeed || isCalendar) {
        log.debug("[-] skipping... ", { url: request.loadedUrl });
        return;
      }

      const looksLikeEventPath = containsEventPath(path);
      if (!looksLikeEventPath) {
        log.debug("[-] skipping... not an event page", {
          url: request.loadedUrl,
        });
        return;
      }

      if (path.includes("/list/")) {
        log.debug("[-] skipping... list page", { url: request.loadedUrl });
        return;
      }

      const pathParts = path.split("/");
      if (pathParts.length > MAX_PATH_PARTS) {
        log.debug("[-] skipping... path too long", {
          url: request.loadedUrl,
        });
        return;
      }

      const encodedLink = encodeURIComponent(request.loadedUrl);
      if (await shouldSkip(encodedLink)) {
        log.debug("[-] skipping... already processed", {
          url: request.loadedUrl,
        });
        return;
      }

      // Keep one capture timestamp across handler retries. The delivery key also includes content.
      const observedAt = String(request.userData.observedAt ?? new Date().toISOString());
      request.userData.observedAt = observedAt;
      const response = Buffer.isBuffer(body) ? body : Buffer.from(body);
      const title = $("title").text();
      log.info(`${title}`, { url: request.loadedUrl });

      const imageUrls = $("img")
        .map((_, el) => $(el).attr("src"))
        .get()
        .join("\n");

      $("style").remove();
      $("script").remove();
      const pageContent = $("body").text().replace(/\s+/g, " ").trim();
      const lengthLimit = pageContent.length > MAX_PAGE_CONTENT_LENGTH ? MAX_PAGE_CONTENT_LENGTH : pageContent.length;
      const truncatedPageContent = pageContent.substring(0, lengthLimit);
      const fullContent = [request.loadedUrl, truncatedPageContent, imageUrls].join("\n");
      // console.log(fullContent);
      let eventData;
      try {
        eventData = await extractEventDataFromPage(fullContent);
      } catch {
        // Failed extraction is evidence too: persist a quarantined capture before retrying.
        await capture(
          { loadedUrl: request.loadedUrl, extractionError: "Extraction failed" },
          response,
          observedAt,
          context,
        );
        throw new Error("Extraction failed");
      }
      await capture({ ...eventData, loadedUrl: request.loadedUrl }, response, observedAt, context);
    } catch {
      // Let Crawlee retry failed persistence; never log raw payloads or credential-bearing errors.
      throw new Error("Event extraction or evidence persistence failed");
    } finally {
      if (isScopedDiscoveryLink(context.loadedUrl, context))
        await enqueueLinks({
          strategy: "same-hostname",
          // Propagate only discovery scope, never the parent page's capture/retry timestamp.
          userData: { discoveryVenueId: context.discoveryVenueId, discoveryUrl: context.discoveryUrl },
          transformRequestFunction: (next) => (isScopedDiscoveryLink(next.url, context) ? next : false),
          globs: [
            "!*/photobooth/*",
            "!*/www.arrobanat.com*",
            "!*format=ical*",
            "!*ical=1*",
            "!*/gallery/*",
            "!*(format=ical|format=json|format=xml|format=rss)*",
            "!*(.jpg|.jpeg|.png|.gif|.svg|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.tar|.gz|.bz2|.xz|.pdf|.doc|.docx|.xls|.xlsx|.ppt|.pptx|.mp3|.mp4|.avi|.mov|.wmv|.flv|.m4v|.webm|.ogg|.webp|.ico|.css|.js|.json|.xml|.rss|.zip|.rar|.7z|.)",
            "!*/photo/*",
          ],
        });
    }
  });

  return router;
}

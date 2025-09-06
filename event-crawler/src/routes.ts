import { createCheerioRouter } from "crawlee";
import { extractEventDataFromPage } from "./utils/openai.js";
import { containsEventPath } from "./utils/parsing.js";

const MAX_PAGE_CONTENT_LENGTH = 15_000;
const MAX_PERFORMERS_PER_EVENT = 15;
const MAX_PATH_PARTS = 10;

export async function getRouter(ignoreLinks: string[] = []) {
  const router = createCheerioRouter();
  router.addDefaultHandler(
    async ({ request, $, pushData, enqueueLinks, log }) => {
      log.info(request.url);

      if (!request.loadedUrl) {
        return;
      }
      const urlObj = new URL(request.loadedUrl);
      const path = urlObj.pathname;

      try {
        const isRSSFeed = request.loadedUrl.endsWith(".rss");
        const isCalendar =
          request.loadedUrl.includes("ical=1") ||
          request.loadedUrl.includes("format=ical");
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
        if (ignoreLinks.includes(encodedLink)) {
          log.debug("[-] skipping... already processed", {
            url: request.loadedUrl,
          });
          return;
        }

        const title = $("title").text();
        log.info(`${title}`, { url: request.loadedUrl });

        const imageUrls = $("img")
          .map((_, el) => $(el).attr("src"))
          .get()
          .join("\n");

        $("style").remove();
        $("script").remove();
        const pageContent = $("body").text().replace(/\s+/g, " ").trim();
        const lengthLimit =
          pageContent.length > MAX_PAGE_CONTENT_LENGTH
            ? MAX_PAGE_CONTENT_LENGTH
            : pageContent.length;
        const truncatedPageContent = pageContent.substring(0, lengthLimit);
        const fullContent = [
          request.loadedUrl,
          truncatedPageContent,
          imageUrls,
        ].join("\n");
        // console.log(fullContent);
        const eventData = await extractEventDataFromPage(fullContent);

        const numOfPerformers = eventData?.performers?.length ?? 0;
        if (numOfPerformers >= MAX_PERFORMERS_PER_EVENT) {
          log.debug("[-] skipping... no performers", {
            url: request.loadedUrl,
          });
          return;
        }

        await pushData({
          loadedUrl: request.loadedUrl,
          ...eventData,
        });
      } catch (e: any) {
        log.error(e);
      } finally {
        await enqueueLinks({
          strategy: "same-hostname",
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
    },
  );

  return router;
}

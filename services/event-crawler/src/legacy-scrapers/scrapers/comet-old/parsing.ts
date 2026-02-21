import type { Page } from "puppeteer";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /calendar/
  // It will not match if there's only /calendar with nothing after
  const eventNameRegex = /^\/live-music-calendar\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);
  return match ? match[1] : null;
}

export async function getArtists(page: Page): Promise<string[]> {
  try {
    // Use evaluate to capture text content
    const artists = await page.evaluate(() => {
      function getTextContent(element: Element | ChildNode): string {
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

      const container = document.querySelector(".eventitem-title");
      if (!container) {
        return [];
      }
      const titleText = getTextContent(container).trim();

      return titleText
        .replace("and", ",")
        .replace(", ,", ",")
        .split(",")
        .map((item) => item.trim())
        .filter((item) => item !== "");
    });

    return artists;
  } catch (e) {
    console.error(`[!!!] something broke, ${e}`);
    return [];
  }
}

export async function getDate(page: Page): Promise<string[]> {
  try {
    // Use evaluate to capture text content
    const date = await page.evaluate(() => {
      function getTextContent(element: Element | ChildNode): string {
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

      const container = document.querySelector(".event-date");

      if (!container) {
        return [];
      }
      const titleText = getTextContent(container).trim();

      return titleText.split(",").map((item) => item.trim());
    });

    return date;
  } catch (e) {
    console.error(`[!!!] something broke, ${e}`);
    return [];
  }
}

export async function getTime(page: Page): Promise<string[]> {
  try {
    // Use evaluate to capture text content
    const time = await page.evaluate(() => {
      function getTextContent(element: Element | ChildNode): string {
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

      const container = document.querySelector(".event-time-12hr-start");

      if (!container) {
        return [];
      }
      const titleText = getTextContent(container).trim();

      return titleText.split(",").map((item) => item.trim());
    });

    return time;
  } catch (e) {
    console.error(`[!!!] something broke, ${e}`);
    return [];
  }
}

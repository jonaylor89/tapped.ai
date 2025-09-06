import type { Page } from "puppeteer";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Exclude private events from bookings

  if (pathname.includes("private")) {
    return null;
  }

  // Regular Expression to capture the event name after /events/
  // It will not match if there's only /events with nothing after
  const eventNameRegex = /\/events\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);

  return match ? match[1] : null;
}

export function parseTicketPrice(priceText: string) {
  let ticketPrice;
  let doorPrice;

  const priceRegex = /\$\d+/g;
  const prices = priceText.match(priceRegex) ? priceText.match(priceRegex) : [];
  if (prices && prices.length !== 0) {
    if (prices.length == 1) {
      ticketPrice = Number(prices[0].trim().slice(1));
      doorPrice = ticketPrice;
    } else {
      ticketPrice = Number(prices[0].trim().slice(1));
      doorPrice = Number(prices[1].trim().slice(1));
    }
  }
  return [ticketPrice ?? null, doorPrice ?? null];
}

export async function parseDescription(page: Page): Promise<string | null> {
  return await page.evaluate(() => {
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

    const container = document.querySelector(".eventitem-column-content");

    if (!container) {
      return "";
    }
    return getTextContent(container).trim();
  });
}
//   // Regular Expression to capture the event name after /calendar/
//   // It will not match if there's only /calendar with nothing after
//   const eventNameRegex = /^\/event\/(.+)$/;

//   // Apply the regex and return the captured group if matched, otherwise null
//   const match = pathname.match(eventNameRegex);
//   return match ? match[1] : null;
// }

export async function parseDates(page: Page) {
  const dateText = await page.evaluate(() => {
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

    const container = document.querySelector(
      ".eventitem-meta.event-meta.event-meta-date-time-container",
    );

    if (!container) {
      return "";
    }
    return getTextContent(container).trim();
  });

  //console.log(dateText)

  // Regular expression pattern to match date and time
  const dateTimeRegex =
    /(\w+),\s+(\w+)\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}:\d{2}\s+(?:AM|PM))\s*(?:-|to)?\s*(\d{1,2}:\d{2}\s*(?:AM|PM))?(?:.*?(\w+),\s+(\w+)\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}:\d{2}\s+(?:AM|PM)))?/gms;

  // Array to store matched dates and times
  const matches = [];

  // Match dates and times in the HTML content
  let match;
  while ((match = dateTimeRegex.exec(dateText)) !== null) {
    if (match[7]) {
      matches.push({
        startDateTime:
          match[2] + " " + match[3] + " " + match[4] + " " + match[5],
        endDateTime:
          match[8] + " " + match[9] + " " + match[10] + " " + match[11],
      });
    } else {
      matches.push({
        startDateTime:
          match[2] + " " + match[3] + " " + match[4] + " " + match[5],
        endDateTime:
          match[2] + " " + match[3] + " " + match[4] + " " + match[6],
      });
    }
  }
  // Convert matched dates and times to Date objects
  const startTime = new Date(matches[0].startDateTime);
  const endTime = new Date(matches[0].endDateTime);

  return {
    startTime,
    endTime,
  };
}

export async function parseArtists(
  title: string,
  description: string,
): Promise<{ artists: string[]; isMusicEvent: boolean }> {
  const parser = new JsonOutputFunctionsParser();
  const extractionFunctionSchema = {
    name: "extractor",
    description: "Extracts fields from the input.",
    parameters: {
      type: "object",
      properties: {
        artistNames: {
          type: "array",
          items: {
            type: "string",
          },
          description:
            "The performers for this event or an empty array if there aren't any",
        },
        isMusicEvent: {
          type: "boolean",
          description: "Whether the event is a music event or not.",
        },
      },
      required: ["artistNames", "isMusicEvent"],
    },
  };

  const llm = new ChatOpenAI({
    modelName: "gpt-3.5-turbo",
  });
  const runnable = llm
    .bind({
      functions: [extractionFunctionSchema],
      function_call: { name: "extractor" },
    })
    .pipe(parser);

  const systemMsg = new SystemMessage(`
    your job is to extract information about an event at the nightclub "Nighthorse" from the title and description'
    None of these are performers names "Nighthorse", "Bar", "Karaoke", "Mingle", "SOLD OUT", Open Mic, etc".
    if you find that the event doesn't to be an event related to music (e.g. a comedy show), set the isMusicEvent to false.'
    `);
  const msg = new HumanMessage(`
                    the title: "${title}"
                    the description: "${description}"
                `);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    artistNames?: string[];
    isMusicEvent?: boolean;
  };

  // console.log({ sum: event.summary, res });
  const artistNames = res.artistNames ?? [];
  const isMusicEvent = res.isMusicEvent ?? false;

  return { artists: artistNames, isMusicEvent };
}

export const sanitizeUsername = (artistName: string) => {
  // Convert name to lowercase
  let username = artistName.toLowerCase();

  // Replace spaces with a hyphen
  username = username.replace(/\s+/g, "_");

  // Remove disallowed characters (only keep letters, numbers, hyphens, and underscores)
  username = username.replace(/[^a-z0-9_]/g, "");

  return username;
};

export async function getFlierUrl(page: Page) {
  try {
    return await page.evaluate(() => {
      const img = document.querySelector(".event-detail-banner-image");
      if (!img) {
        return null;
      }

      const src = img.getAttribute("src");
      return src;
    });
  } catch (error) {
    console.error("[-] error getting flier url", error);
    return null;
  }
}

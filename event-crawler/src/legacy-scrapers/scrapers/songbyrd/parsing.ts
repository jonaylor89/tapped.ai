import type { Page } from "puppeteer";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /events-list/year/month/day
  // It will not match if there's only /events-list with nothing after
  const eventNameRegex = /\/event\/(.+)$/;

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

    const container = document.querySelector(".wpem-single-event-body-content");

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
  const element = await page.$$eval(
    ".wpem-event-date-time",
    (el) => el[0].outerHTML,
  );

  const htmlContent = element;

  // Regular expression pattern to match date and time
  const dateTimeRegex = /(\d{4}-\d{2}-\d{2})\s+@\s+(\d{2}:\d{2}\s+[AP]M)/g;

  // Array to store matched dates and times
  const matches = [];

  // Match dates and times in the HTML content
  let match;
  while ((match = dateTimeRegex.exec(htmlContent)) !== null) {
    matches.push({
      date: match[1],
      time: match[2],
    });
  }

  // Convert matched dates and times to Date objects
  const startTime = new Date(matches[0].date + " " + matches[0].time);
  const endTime = new Date(matches[1].date + " " + matches[1].time);

  return {
    startTime,
    endTime,
  };
}

export async function parseArtists(
  title: string,
  description: string,
): Promise<string[]> {
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
            "The musicians listed in the title of this event or an empty array if none are found.",
        },
      },
      required: ["artistNames"],
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
    you're job is to extract the artist names from the title and description of an event.'
    The band names are unique so don't include names that might describe the event or location like "Nights", "OTP", "SOLD OUT", etc"
    `);
  const msg = new HumanMessage(`
                    the title: "${title}"

                    the description: "${description}"
                `);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    artistNames?: string[];
  };

  // console.log({ sum: event.summary, res });
  const artistNames = res.artistNames ?? [];
  return artistNames;
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
      const img = document.querySelector(".wpem-event-single-image-rmt img");
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

import { Page } from "puppeteer";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /events-list/year/month/day
  // It will not match if there's only /events-list with nothing after
  const eventNameRegex = /\/events\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);

  return match ? match[1] : null;
}

export function parseTicketPrice(description: string) {
  let ticketPrice;
  let doorPrice;

  const priceRegex = /\$\d+/g;
  const prices = description.match(priceRegex)
    ? description.match(priceRegex)
    : [];
  if (prices && prices.length !== 0) {
    if (prices.length == 1) {
      ticketPrice = Number(prices[0].trim().slice(1));
      doorPrice = ticketPrice;
    } else {
      ticketPrice = Number(prices[0].trim().slice(1));
      doorPrice = Number(prices[1].trim().slice(1));
    }
  }
  return [ticketPrice, doorPrice];
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

    const container = document.querySelector(".shortDesc");

    if (!container) {
      return "";
    }
    return getTextContent(container).trim();
  });
}

export function parseTimes(startTimeStr: string[], endTimeStr: string[]) {
  const [startTime, endTime] = [startTimeStr, endTimeStr].map(
    (match: string[]) => {
      // Function to convert month name to month index

      const monthNameToIndex: {
        [key: string]: number;
      } = {
        Jan: 0,
        Feb: 1,
        Mar: 2,
        Apr: 3,
        May: 4,
        Jun: 5,
        Jul: 6,
        Aug: 7,
        Sep: 8,
        Oct: 9,
        Nov: 10,
        Dec: 11,
      };

      const year = parseInt(match[2]);
      const monthStr: string = match[0];
      const month: number = monthNameToIndex[monthStr];
      const day = parseInt(match[1]);
      const timeStr = match[3];

      // Convert matches to JavaScript Date objects
      const date = new Date(
        year,
        month,
        day,
        timeStr.endsWith("PM")
          ? parseInt(timeStr.split(":")[0]) + 12
          : parseInt(timeStr.split(":")[0]),
        parseInt(timeStr.split(":")[1]),
      );

      return date;
    },
  );

  return {
    startTime,
    endTime,
  };
}

export async function parseArtists(title: string): Promise<string[]> {
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

  const llm = new ChatOpenAI({});
  const runnable = llm
    .bind({
      functions: [extractionFunctionSchema],
      function_call: { name: "extractor" },
    })
    .pipe(parser);

  const systemMsg = new SystemMessage(`
    your job it to extract the names of the musicians from the title of an event.
    the website this was copied from uses all kind of delimiters such as "&" "W." "w/", "W/" or ","
    but also longer natural language delimiters like "with support from", "wth special guest", etc. Don't include these delimiters in the names.
    The band names are unique so don't include names that might describe the event or location like "Nights" or "OTP".
    `);
  const msg = new HumanMessage(`
      the event title: "${title}"
  `);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    artistNames?: string[];
  };

  // console.log({ sum: event.summary, res });
  const artistNames = res.artistNames ?? [];
  return artistNames;
}

export const parseFlierUrl = async (page: Page): Promise<string | null> => {
  try {
    return await page.evaluate(() => {
      const img = document.querySelector("div.col.l5.center img");
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
};

export const sanitizeUsername = (artistName: string) => {
  // Convert name to lowercase
  let username = artistName.toLowerCase();

  // Replace spaces with a hyphen
  username = username.replace(/\s+/g, "_");

  // Remove disallowed characters (only keep letters, numbers, hyphens, and underscores)
  username = username.replace(/[^a-z0-9_]/g, "");

  return username;
};

import { ChatOpenAI } from "@langchain/openai";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import type { Page } from "puppeteer";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /calendar/
  // It will not match if there's only /calendar with nothing after
  const eventNameRegex = /^\/event\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);
  return match ? match[1] : null;
}

export async function getEventDetails(page: Page): Promise<{
  artists: string[];
  startTime: Date | null;
  endTime: Date | null;
  doorPrice: number | null;
  ticketPrice: number | null;
  title: string | null;
  description: string | null;
}> {
  const title = await getTitle(page);
  const description = await getDescription(page);
  const details = await getDetails(page);

  const { artists, startTime, endTime, doorPrice, ticketPrice } =
    await parseDetails(title, description, details);

  return {
    artists,
    startTime,
    endTime,
    doorPrice,
    ticketPrice,
    title,
    description,
  };
}

async function parseDetails(
  title: string | null,
  description: string | null,
  details: string | null,
): Promise<{
  artists: string[];
  startTime: Date | null;
  endTime: Date | null;
  doorPrice: number | null;
  ticketPrice: number | null;
}> {
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
        startTime: {
          type: "string",
          description:
            "The start time of the event in the format 'YYYY-MM-DDTHH:MM:SS'",
        },
        endTime: {
          type: "string",
          description:
            "The end time of the event in the format 'YYYY-MM-DDTHH:MM:SS'",
        },
        doorPrice: {
          type: "number",
          description:
            "The price of the event at the door or null if not provided. (and 0 if it's free)",
        },
        ticketPrice: {
          type: "number",
          description:
            "The price of the event for tickets or null if not provided. (and 0 if it's free)",
        },
      },
      required: [
        "artistNames",
        "startTime",
        "endTime",
        "doorPrice",
        "ticketPrice",
      ],
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
  your job it to extract information about the event from the title, description and details of the event.
  `);
  const msg = new HumanMessage(`
    title: "${title ?? ""}"
   -------------------------
    description: "${description ?? ""}"
    -------------------------
    details: "${details ?? ""}"
`);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    artistNames?: string[];
    startTime?: string;
    endTime?: string;
    doorPrice?: number;
    ticketPrice?: number;
  };

  // console.log({ sum: event.summary, res });
  const artists = res.artistNames ?? [];
  const startTime = res.startTime ? new Date(res.startTime) : null;
  const endTime = res.endTime ? new Date(res.endTime) : null;
  const doorPrice = res.doorPrice ?? null;
  const ticketPrice = res.ticketPrice ?? null;

  return {
    artists,
    startTime,
    endTime,
    doorPrice,
    ticketPrice,
  };
}

async function getDetails(page: Page): Promise<string | null> {
  try {
    const details = await page.$eval(
      ".tribe-events-event-meta",
      (el) => el.textContent?.trim() ?? "",
    );
    return details;
  } catch (e) {
    return null;
  }
}

async function getDescription(page: Page): Promise<string | null> {
  try {
    const description = await page.$eval(
      ".tribe-events-single-event-description",
      (el) => el.textContent?.trim() ?? "",
    );
    return description;
  } catch (e) {
    return null;
  }
}

async function getTitle(page: Page): Promise<string | null> {
  try {
    const title = await page.$eval(
      ".tribe-events-single-event-title",
      (el) => el.textContent?.trim() ?? "",
    );
    return title;
  } catch (e) {
    return null;
  }
}

export async function getFlierUrl(page: Page) {
  try {
    const url = await page.$eval(".tribe-events-event-image img", (el) =>
      el.getAttribute("src"),
    );
    return url;
  } catch (e) {
    return null;
  }
}

export async function getArtists(page: Page): Promise<string[]> {
  const artistElements = await page.$$eval(
    ".tribe-events-single-event-title",
    (elements) => elements.map((el) => el.textContent?.trim() ?? ""),
  );
  return artistElements;
}

export async function getDate(page: Page): Promise<string[]> {
  const dateElements = await page.$$eval(
    ".tribe-event-date-start",
    (elements) => elements.map((el) => el.textContent?.trim() ?? ""),
  );
  return dateElements;
}

export async function getTime(page: Page): Promise<string[]> {
  const timeElements = await page.$$eval(
    ".tribe-events-schedule h3",
    (elements) => elements.map((el) => el.textContent?.trim() ?? ""),
  );
  return timeElements;
}

import type { Page } from "puppeteer";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { getTextContent } from "../../utils/text_content";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /calendar/
  // It will not match if there's only /calendar with nothing after
  const eventNameRegex = /^\/events\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);
  return match ? match[1] : null;
}

export async function getFlierUrl(page: Page) {
  try {
    return await page.evaluate(() => {
      const img = document.querySelector(
        ".sqs-image-shape-container-element img",
      );
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

export async function parsePage(page: Page) {
  // get page content
  const pageContent = await getTextContent(page, ".eventitem");

  // pass content to chatgpt
  const {
    isMusicEvent,
    artistNames,
    eventTitle,
    eventDescription,
    startTime,
    endTime,
  } = await extractItemsFromPage(pageContent);

  const startDate = new Date(startTime);
  const endDate = new Date(endTime);

  return {
    isMusicEvent,
    title: eventTitle,
    description: eventDescription,
    artists: artistNames,
    startTime: startDate,
    endTime: endDate,
  };
}

async function extractItemsFromPage(pageContent: string) {
  const parser = new JsonOutputFunctionsParser();
  const extractionFunctionSchema = {
    name: "extractor",
    description: "Extracts fields from the input.",
    parameters: {
      type: "object",
      properties: {
        isMusicEvent: {
          type: "boolean",
          description: "Whether this event is a music event.",
        },
        artistNames: {
          type: "array",
          items: {
            type: "string",
          },
          description:
            "the specific names of the musicians/performers/Djs for the event",
        },
        eventTitle: {
          type: "string",
          description: "The title of the event.",
        },
        eventDescription: {
          type: "string",
          description: "The description of the event.",
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
      },
      required: [
        "isMusicEvent",
        "artistNames",
        "eventTitle",
        "eventDescription",
        "startTime",
        "endTime",
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
    you're in charge of parsing the content of a webpage for an event and extracting the event details.
    The venue that runs these events hosted both events with and without music.
    I'm only interested in the music events. Given the page content, extrac the necessary details
    `);
  const msg = new HumanMessage(`
      the page content: "${pageContent}"
  `);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    artistNames?: string[];
    startTime?: string;
    endTime?: string;
    eventTitle?: string;
    eventDescription?: string;
    isMusicEvent?: boolean;
  };

  const artistNames = res.artistNames ?? [];
  return {
    artistNames,
    startTime: res.startTime ?? new Date(),
    endTime: res.endTime ?? new Date(),
    eventTitle: res.eventTitle ?? "",
    eventDescription: res.eventDescription ?? "",
    isMusicEvent: res.isMusicEvent ?? false,
  };
}

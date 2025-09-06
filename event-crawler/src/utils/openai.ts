import { Option, EventData } from "../types.js";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { addHours, getDateFromStr } from "./date.js";

export async function extractEventDataFromPage(
  pageContent: string,
): Promise<Option<Omit<EventData, "venue" | "crawlerInfo" | "eventId">>> {
  const parser = new JsonOutputFunctionsParser();
  const extractionFunctionSchema = {
    name: "extractor",
    description: "Extracts fields from the input.",
    parameters: {
      type: "object",
      properties: {
        isMusicEvent: {
          type: "boolean",
          description: "Whether this website is for a music event.",
        },
        performerNames: {
          type: "array",
          items: {
            type: "string",
          },
          description:
            "the specific names of the musicians/performers/Djs for the event. do not include the venue name or generic names for the performers like 'international guest', 'resident DJ', 'special guest', etc.",
        },
        eventTitle: {
          type: "string",
          description: "The title of the event or an empty string.",
        },
        eventDescription: {
          type: "string",
          description: "The description of the event or an empty string.",
        },
        startTime: {
          type: "string",
          description:
            "The start time or when the doors open for the event in the format 'YYYY-MM-DDTHH:MM:SS'",
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
        flierUrl: {
          type: "string",
          description:
            "The URL of the flier for the event or an empty string. MUST BE A URL, DO NOT USE a placeholder like 'N/A' or 'URL_FOR_THE_FLIER' or '[FLIER URL]' or similar.",
        },
        eventUrl: {
          type: "string",
          description:
            "the URL for the ticketing page of the event or an empty string. (usually eventbrite.com, shotgun.live, dice.fm, etix.com, etc.). MUST BE A URL, DO NOT use a placeholder like 'N/A' or 'URL_FOR_THE_EVENT' or '[EVENT URL]' or similar",
        },
      },
      required: [
        "isMusicEvent",
        "performerNames",
        "eventTitle",
        "eventDescription",
        "startTime",
        "endTime",
        "doorPrice",
        "ticketPrice",
        // "flierUrl",
        // "eventUrl"
      ],
    },
  };

  const llm = new ChatOpenAI({
    modelName: "gpt-4o-mini",
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
      I'm only interested in the music events. Given the page content, extract the necessary details
      `);
  const msg = new HumanMessage(`
        the page content: "${pageContent}"
    `);
  const res = (await runnable.invoke([systemMsg, msg])) as {
    performerNames?: string[];
    startTime?: string;
    endTime?: string;
    eventTitle?: string;
    eventDescription?: string;
    isMusicEvent?: boolean;
    ticketPrice?: number;
    doorPrice?: number;
    flierUrl?: string;
    eventUrl?: string;
  };

  const startTime = getDateFromStr(res.startTime);
  const endTime = getDateFromStr(res.endTime, () => addHours(startTime, 1));

  const performerNames = res.performerNames ?? [];
  const flierUrl = res.flierUrl?.startsWith("https://") ? res.flierUrl : null;
  const url = res.eventUrl?.startsWith("https://") ? res.eventUrl : null;
  return {
    performers: performerNames,
    startTime,
    endTime,
    title: res.eventTitle ?? null,
    description: res.eventDescription ?? null,
    isMusicEvent: res.isMusicEvent ?? false,
    ticketPrice: res.ticketPrice ?? 0,
    doorPrice: res.doorPrice ?? 0,
    flierUrl,
    url,
  };
}

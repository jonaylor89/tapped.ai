import type { Page } from "puppeteer";
import { ChatOpenAI } from "@langchain/openai";
import { RunnableSequence } from "@langchain/core/runnables";
import { CommaSeparatedListOutputParser } from "langchain/output_parsers";
import { PromptTemplate } from "@langchain/core/prompts";

async function getPerformersFromEventDetails(
  title: string,
  description: string,
): Promise<string[]> {
  // Instantiate the parser
  const parser = new CommaSeparatedListOutputParser();

  // Instantiate the ChatOpenAI class
  const model = new ChatOpenAI({ modelName: "gpt-3.5-turbo" });

  // Create a new runnable, bind the function to the model, and pipe the output through the parser

  const promptTemplate = `
Title: {title}
Description: {description}

Based on the event details above, please list the musicians who will be performing at this event.
Some of the events involve cover bands and tribute bands, so don't include the original artist's name in the list.

{formatInstructions}
    `;

  const runnable = RunnableSequence.from([
    PromptTemplate.fromTemplate(promptTemplate),
    model,
    parser,
  ]);

  // Invoke the runnable with an input
  const result = await runnable.invoke({
    title,
    description,
    formatInstructions: parser.getFormatInstructions(),
  });

  return result;
}

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /calendar/
  // It will not match if there's only /calendar with nothing after
  const eventNameRegex = /^\/event\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);
  return match ? match[1] : null;
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

export function timeTextToTimestamp(timeString: string): string | null {
  // Extract hour and minute components
  const match = timeString.match(/(\d+)(?::(\d+))?(am|pm)?/i);
  if (!match) {
    console.log("[!!!] match not found");
    return null;
  }

  const [, hourString, minuteString] = match;

  let hour = parseInt(hourString, 10);
  const minute = parseInt(minuteString ?? 0, 10);

  // Adjust for AM/PM
  if (/pm/i.test(timeString) && hour < 12) {
    hour += 12;
  }
  if (/am/i.test(timeString) && hour === 12) {
    hour = 0;
  }

  // Format components to have leading zeros if necessary
  const formattedHour = hour.toString().padStart(2, "0");
  const formattedMinute = minute.toString().padStart(2, "0");

  const timestamp = `${formattedHour}:${formattedMinute}:00`;

  return timestamp;
}

export function parseDateString(dateString: string, timestamp: string) {
  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const parts = dateString.split(", ");
  const dayMonth = parts[1].split(" ");

  // Assuming a default year (e.g., current year)
  const year = new Date().getFullYear();

  const month = (months.indexOf(dayMonth[0]) + 1).toString().padStart(2, "0");
  const day = (dayMonth[1] ?? "01").padStart(2, "0");

  const dateTimestamp = `${year}-${month}-${day}T${timestamp}`;

  return new Date(dateTimestamp);
}

export async function getTitle(page: Page): Promise<string | null> {
  const titleElement = await page.waitForSelector("#eventTitle");
  if (!titleElement) {
    console.log("[-] element not found");
    return null;
  }

  const title = (
    (await page.evaluate((element) => element.textContent, titleElement)) ?? ""
  ).trim();

  return title;
}

export async function getDescription(page: Page): Promise<string | null> {
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

    const container = document.querySelector(".singleEventDescription");

    if (!container) {
      return "";
    }
    return getTextContent(container).trim();
  });
}

export async function getTimes(page: Page): Promise<{
  startTime: Date;
  endTime: Date;
} | null> {
  const dateString = await page.evaluate(() => {
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

    const container = document.querySelector(".eventStDate");

    if (!container) {
      return null;
    }

    const dateText = getTextContent(container).trim();

    return dateText;
  });

  if (!dateString) {
    console.log("[-] date string not found");
    return null;
  }

  const timeString = await page.evaluate(() => {
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

    const container = document.querySelector(".eventDoorStartDate");

    if (!container) {
      return null;
    }

    const timeText = getTextContent(container).trim();

    const pattern = /(?<=Show:\s*)(\d{1,2}(?::\d{2})?(?:[ap]m)?)\b/g;
    const match = timeText.match(pattern);
    if (!match) {
      return null;
    }

    const showStartTime = match[0];
    return showStartTime;
  });
  if (!timeString) {
    console.log("[!!!] time string not found");
    return null;
  }

  const timestamp = timeTextToTimestamp(timeString);
  if (!timestamp) {
    console.log(`[!!!] timestamp couldn't be parsed ${timeString}`);
    return null;
  }

  const startTime = parseDateString(dateString, timestamp);
  const endTime = new Date(startTime);
  endTime.setHours(endTime.getHours() + 2);

  return {
    startTime,
    endTime,
  };
}

export async function getArtists(
  title: string,
  description: string,
): Promise<string[]> {
  const artists = getPerformersFromEventDetails(title, description);
  return artists;
}

export async function getFlierUrl(page: Page): Promise<string | null> {
  return await page.evaluate(() => {
    const img = document.querySelector(".rhp-events-event-image img");
    if (!img) {
      return null;
    }

    const src = img.getAttribute("src");
    return src;
  });
}

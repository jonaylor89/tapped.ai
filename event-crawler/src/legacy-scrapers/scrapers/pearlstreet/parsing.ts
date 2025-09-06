import { Page } from "puppeteer";
import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { JsonOutputFunctionsParser } from "langchain/output_parsers";

export function getEventNameFromUrl(url: string) {
  const pathname = new URL(url).pathname;

  // Regular Expression to capture the event name after /events-list/year/month/day         
  // It will not match if there's only /events-list with nothing after        
  const eventNameRegex = /\/tm-event\/(.+)$/;

  // Apply the regex and return the captured group if matched, otherwise null
  const match = pathname.match(eventNameRegex);

  return match ? match[1] : null;
}

export function parseTicketPrice(priceContent: string) {
  let ticketPrice;
  let doorPrice;
  if (priceContent.includes("-")) {
    const [ticketString, doorString]  = priceContent.split("-");
    
    ticketPrice = Number(ticketString.trim().slice(1));
    doorPrice = Number(doorString.trim().slice(1))
    
  } else {
    if (priceContent !== "") {
      ticketPrice = Number(priceContent.trim().slice(1));

      doorPrice = ticketPrice;

    }
  }
  return [ticketPrice, doorPrice]
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

    const container = document.querySelector(".tw-description");

    if (!container) {
      return "";
    }
    return getTextContent(container).trim();
  });
}

export function parseTimes(startTimeStr: string[], endTimeStr: string[]) {

  const [startTime, endTime] = [startTimeStr, endTimeStr].map((match: string[]) => {
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
    const timeStr = match[3]

    // Convert matches to JavaScript Date objects
    const date = new Date(
      year,
      month,
      day,
      monthStr.endsWith("PM")
        ? parseInt(timeStr.split(":")[0]) + 12
        : parseInt(timeStr.split(":")[0]),
      parseInt(timeStr.split(":")[1])
    );

    return date;
  });

  return {
    startTime,
    endTime,
  }
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
          description: "The musicians listed in the title of this event or an empty array if none are found.",
        },
      },
      required: ["artistNames"],
    },
  };

  const llm = new ChatOpenAI({})
  const runnable = llm
    .bind({
      functions: [extractionFunctionSchema],
      function_call: { name: "extractor" },
    })
    .pipe(parser);

  const systemMsg = new SystemMessage(`
    can you parse this string into an array with the names of all the musicians. 
    the website this was copied from uses all kind of delimiters such as "&" "W." "w/", "W/" or "," 
    but also longer natural language delimiters like "with support from". 
    These are mostly rock, country, folk, soul, bluegrass, rhythm and blues musicians so things like numbers and symbols are not part of the name 
    `);
  const msg = new HumanMessage(`
                    the string: "${title}"
                `);
  const res = await runnable.invoke([
    systemMsg,
    msg,
  ]) as { artistNames?: string[] };

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

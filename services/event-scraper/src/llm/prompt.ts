import type {
  EventCategory,
  EventStatus,
  ExtractContext,
  ExtractedEvent,
  JsonSchema,
  LlmClient,
  LlmJsonRequest,
  Page,
} from "../types.js";
import { parsePriceText } from "../validate/price.js";
import { localDate, weekdayOf } from "../validate/time.js";
import { type ChunkOptions, chunkText, cleanPageText } from "./text.js";

/**
 * LLM fallback extraction: a strict JSON schema asking for a LIST of events with verbatim evidence quotes, plus the
 * prompt that grounds the model in the venue, its IANA timezone and "today". Output is mapped to ExtractedEvent and
 * still goes through deterministic validation (which rejects any event whose quotes are not on the page).
 */

export const LLM_EXTRACTOR_NAME = "llm";
export const EVENT_SCHEMA_NAME = "venue_events";

const nullable = (type: string, extra: Record<string, unknown> = {}) => ({ type: [type, "null"], ...extra });

/** Strict structured-output schema (every property required; optional values are nullable). */
export const EVENT_LIST_SCHEMA: JsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["events"],
  properties: {
    events: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "title",
          "start_date",
          "start_time",
          "end_date",
          "end_time",
          "doors_time",
          "raw_date_text",
          "performers",
          "description",
          "price_text",
          "is_free",
          "status",
          "category",
          "event_url",
          "ticket_url",
          "image_url",
          "evidence",
        ],
        properties: {
          title: { type: "string", description: "Event title exactly as shown (no added words)." },
          start_date: {
            type: "string",
            description: "YYYY-MM-DD when the page shows the year, otherwise --MM-DD. Never guess a year.",
          },
          start_time: nullable("string", {
            description: "Show start, 24h HH:mm, local venue time; null if not shown.",
          }),
          end_date: nullable("string", {
            description: "YYYY-MM-DD or --MM-DD only if the event ends on another date.",
          }),
          end_time: nullable("string", { description: "24h HH:mm; null if not shown." }),
          doors_time: nullable("string", { description: "Doors time 24h HH:mm; null if not shown." }),
          raw_date_text: nullable("string", { description: "The date/time text exactly as printed." }),
          performers: { type: "array", items: { type: "string" }, description: "Performer names as shown." },
          description: nullable("string", { description: "Short description from the page, or null." }),
          price_text: nullable("string", { description: "Price text exactly as printed, e.g. '$15 adv / $20 door'." }),
          is_free: nullable("boolean"),
          status: { type: "string", enum: ["scheduled", "canceled", "postponed", "rescheduled", "sold_out"] },
          category: { type: "string", enum: ["music", "comedy", "open_mic", "theater", "dance", "other"] },
          event_url: nullable("string", { description: "Link to this event's own page, as found in the text." }),
          ticket_url: nullable("string"),
          image_url: nullable("string"),
          evidence: {
            type: "array",
            items: { type: "string" },
            description:
              "1-3 verbatim quotes copied character-for-character from the page. The first quote must contain both the title and the date as printed.",
          },
        },
      },
    },
  },
};

const WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export interface PromptInput {
  venueName: string | null;
  timezone: string;
  now: Date;
  pageUrl: string;
  text: string;
  chunkIndex?: number;
  chunkCount?: number;
}

export const EVENT_SYSTEM_PROMPT = [
  "You extract upcoming public events from a venue's own website text.",
  "Return every distinct event occurrence listed on the page as one item in `events` (recurring events: one item per listed date).",
  "Rules:",
  "- Only use facts written in the text. Never invent titles, dates, times, prices or performers.",
  "- Dates: if the page shows the year use YYYY-MM-DD; if it does not, use --MM-DD. Do not guess the year.",
  "- Times are local venue wall-clock times in 24h HH:mm. Use null when a time is not written.",
  "- 'Doors' times go in doors_time; 'show'/'music'/'starts' times go in start_time.",
  "- evidence: copy 1-3 short quotes VERBATIM (same characters, same spelling) from the text. The first quote must be one continuous passage that contains both the event title and its date exactly as printed (e.g. 'Fri, Nov 6 The Band'); events without such a quote are discarded.",
  "- category: music, comedy, open_mic, theater, dance, or other (trivia, brunch, karaoke, private events, closures, sports, classes, markets).",
  "- status: canceled/postponed/sold_out only when the text says so.",
  "- Lines containing only '---' separate listing items. An event's date, time, price and details are the ones inside the same item as its title, never from a neighbouring item.",
  "- Skip navigation, ads, newsletter text and events at other venues.",
  "- If there are no events, return an empty list.",
].join("\n");

export function buildEventPrompt(input: PromptInput): { system: string; user: string } {
  const today = localDate(input.now, input.timezone);
  const weekday = WEEKDAY_NAMES[weekdayOf(today)];
  const part =
    input.chunkCount && input.chunkCount > 1
      ? `\nThis is part ${(input.chunkIndex ?? 0) + 1} of ${input.chunkCount} of the page; extract events from this part only.`
      : "";
  const user = [
    `Venue: ${input.venueName ?? "(unknown; a city listing page — include the venue name in the description)"}`,
    `Venue timezone (IANA): ${input.timezone}`,
    `Today at the venue: ${weekday} ${today}`,
    `Page URL: ${input.pageUrl}${part}`,
    "",
    "Page text:",
    '"""',
    input.text,
    '"""',
  ].join("\n");
  return { system: EVENT_SYSTEM_PROMPT, user };
}

export function buildEventRequest(input: PromptInput, maxOutputTokens = 8000): LlmJsonRequest {
  const { system, user } = buildEventPrompt(input);
  return { system, user, schemaName: EVENT_SCHEMA_NAME, schema: EVENT_LIST_SCHEMA, maxOutputTokens, temperature: 0 };
}

// ---------------------------------------------------------------------------------------------------------------------
// Response mapping
// ---------------------------------------------------------------------------------------------------------------------

const STATUSES: readonly EventStatus[] = ["scheduled", "canceled", "postponed", "rescheduled", "sold_out"];
const CATEGORIES: readonly EventCategory[] = ["music", "comedy", "open_mic", "theater", "dance", "other"];

const str = (v: unknown): string | null => (typeof v === "string" && v.trim() ? v.trim() : null);

function normTime(v: unknown): string | null {
  const s = str(v);
  if (!s) return null;
  const m = /^(\d{1,2}):(\d{2})/.exec(s);
  if (!m) return null;
  return `${(m[1] as string).padStart(2, "0")}:${m[2]}`;
}

function normDate(v: unknown): string | null {
  const s = str(v);
  if (!s) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(s) || /^--\d{2}-\d{2}$/.test(s)) return s;
  return null;
}

/** Maps the model's JSON to ExtractedEvents. Malformed items are skipped (validation catches the rest). */
export function parseLlmEvents(data: unknown, extractor = LLM_EXTRACTOR_NAME): ExtractedEvent[] {
  const items = (data as { events?: unknown })?.events;
  if (!Array.isArray(items)) return [];
  const out: ExtractedEvent[] = [];
  for (const raw of items) {
    if (!raw || typeof raw !== "object") continue;
    const item = raw as Record<string, unknown>;
    const date = normDate(item.start_date);
    const time = normTime(item.start_time);
    const endDate = normDate(item.end_date);
    const endTime = normTime(item.end_time);
    const priceText = str(item.price_text);
    const parsedPrice = parsePriceText(priceText);
    const evidence = Array.isArray(item.evidence)
      ? item.evidence.filter((q): q is string => typeof q === "string")
      : [];
    const status = STATUSES.includes(item.status as EventStatus) ? (item.status as EventStatus) : null;
    const category = CATEGORIES.includes(item.category as EventCategory) ? (item.category as EventCategory) : null;
    out.push({
      title: str(item.title),
      start: date ? (time ? `${date}T${time}` : date) : null,
      timezone: null,
      startInstant: null,
      end: endDate ? (endTime ? `${endDate}T${endTime}` : endDate) : endTime,
      doors: normTime(item.doors_time),
      description: str(item.description),
      imageUrl: str(item.image_url),
      eventUrl: str(item.event_url),
      ticketUrl: str(item.ticket_url),
      performers: Array.isArray(item.performers)
        ? item.performers.filter((p): p is string => typeof p === "string")
        : [],
      prices: parsedPrice.prices,
      isFree: typeof item.is_free === "boolean" ? item.is_free : parsedPrice.isFree,
      status: status === "scheduled" && parsedPrice.soldOut ? "sold_out" : status,
      category,
      evidence,
      extractor,
      sourceEventId: null,
      rawDateText: str(item.raw_date_text),
    });
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
// End-to-end helper (clean -> chunk -> prompt -> parse -> merge)
// ---------------------------------------------------------------------------------------------------------------------

export interface LlmExtractOptions extends ChunkOptions {
  maxOutputTokens?: number;
}

export interface LlmExtractResult {
  events: ExtractedEvent[];
  chunks: number;
  inputTokens: number;
  outputTokens: number;
  model: string | null;
}

/**
 * Runs the LLM over a page: boilerplate-stripped text, chunked, one structured call per chunk, results merged and
 * de-duplicated (title + start). The LLM client comes from `ctx.llm`; returns no events when it is absent.
 */
export async function extractEventsWithLlm(
  page: Page,
  ctx: ExtractContext,
  options: LlmExtractOptions = {},
): Promise<LlmExtractResult> {
  const result: LlmExtractResult = { events: [], chunks: 0, inputTokens: 0, outputTokens: 0, model: null };
  const llm: LlmClient | undefined = ctx.llm;
  if (!llm) return result;
  const text = cleanPageText(page.text, page.contentType);
  const chunks = chunkText(text, options);
  result.chunks = chunks.length;
  const seen = new Set<string>();
  for (const [index, chunk] of chunks.entries()) {
    const request = buildEventRequest(
      {
        venueName: ctx.venue?.name ?? ctx.source.label ?? null,
        timezone: ctx.timezone,
        now: ctx.now,
        pageUrl: page.finalUrl || page.url,
        text: chunk,
        chunkIndex: index,
        chunkCount: chunks.length,
      },
      options.maxOutputTokens,
    );
    const response = await llm.completeJson(request);
    result.model = response.model;
    result.inputTokens += response.inputTokens ?? 0;
    result.outputTokens += response.outputTokens ?? 0;
    for (const event of parseLlmEvents(response.data)) {
      const key = `${(event.title ?? "").toLowerCase().replace(/\s+/g, " ")}|${event.start ?? ""}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.events.push(event);
    }
  }
  return result;
}

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { LlmError, llmClientFromEnv, OpenAiCompatibleClient } from "../src/llm/openai.js";
import { buildEventPrompt, EVENT_LIST_SCHEMA, extractEventsWithLlm, parseLlmEvents } from "../src/llm/prompt.js";
import { chunkText, cleanPageText, pageToText } from "../src/llm/text.js";
import type { ExtractContext, LlmClient, LlmJsonRequest, LlmJsonResponse, Page, Source } from "../src/types.js";
import { validateEvents } from "../src/validate/validate.js";

const fixture = (name: string) => readFileSync(new URL(`./fixtures/llm/${name}`, import.meta.url), "utf8");
const HTML = fixture("venue-calendar.html");
const RESPONSE = JSON.parse(fixture("venue-calendar.response.json")) as unknown;
const NOW = new Date("2026-11-02T15:00:00Z");

const SOURCE: Source = {
  id: "src-1",
  venueId: "venue-1",
  kind: "html",
  url: "https://example-room.test/shows",
  timezone: "America/Chicago",
  enabled: true,
  label: null,
  origin: "manual",
  fetchIntervalMs: 0,
  createdAt: 0,
  updatedAt: 0,
};

class FakeLlm implements LlmClient {
  readonly requests: LlmJsonRequest[] = [];
  constructor(private readonly respond: (req: LlmJsonRequest, n: number) => unknown) {}
  async completeJson(request: LlmJsonRequest): Promise<LlmJsonResponse> {
    this.requests.push(request);
    return { data: this.respond(request, this.requests.length), model: "fake", inputTokens: 10, outputTokens: 5 };
  }
}

function page(text = HTML): Page {
  return {
    url: SOURCE.url,
    finalUrl: SOURCE.url,
    contentType: "text/html; charset=utf-8",
    text,
    body: new TextEncoder().encode(text),
    fetchedAt: NOW.getTime(),
  };
}

function ctx(llm?: LlmClient): ExtractContext {
  return {
    source: SOURCE,
    venue: {
      id: "venue-1",
      name: "The Example Room",
      address: null,
      lat: null,
      lng: null,
      website: null,
      googlePlaceId: null,
      timezone: "America/Chicago",
      syncedAt: 0,
    },
    timezone: "America/Chicago",
    now: NOW,
    llm,
  };
}

describe("page text", () => {
  test("cleanPageText strips scripts, nav, cookie banners and footers; keeps event text", () => {
    const text = cleanPageText(HTML, "text/html");
    assert.match(text, /The Example Band w\/ Openers & Friends/);
    assert.match(text, /Sat, Nov 7 · 10pm – 2am/);
    assert.doesNotMatch(text, /Taylor Swift/);
    assert.doesNotMatch(text, /cookies/);
    assert.doesNotMatch(text, /newsletter/);
    assert.doesNotMatch(text, /Private Events/);
    // Block elements become separate lines.
    assert.match(text, /Fri, Nov 6\nDoors 7:00pm \/ Show 8:00pm/);
  });

  test("pageToText keeps everything visible (for quote verification)", () => {
    const text = pageToText(HTML, "text/html");
    assert.match(text, /newsletter/);
    assert.doesNotMatch(text, /window\.tracking/);
  });

  test("non-HTML passes through", () => {
    assert.equal(cleanPageText("BEGIN:VCALENDAR\r\nEND:VCALENDAR", "text/calendar"), "BEGIN:VCALENDAR\nEND:VCALENDAR");
  });

  test("chunkText splits on lines with overlap and caps chunk count", () => {
    const lines = Array.from({ length: 400 }, (_, i) => `line ${i} ${"x".repeat(40)}`);
    const chunks = chunkText(lines.join("\n"), { maxChars: 2000, overlapChars: 200, maxChunks: 50 });
    assert.ok(chunks.length > 5);
    for (const c of chunks) assert.ok(c.length <= 2000);
    // Overlap: the last line of chunk 0 starts chunk 1's carried context.
    const lastOfFirst = chunks[0]?.split("\n").at(-1) as string;
    assert.ok(chunks[1]?.includes(lastOfFirst));
    assert.ok(chunks.join("\n").includes("line 399"));
    assert.equal(chunkText(lines.join("\n"), { maxChars: 2000, maxChunks: 2 }).length, 2);
    assert.deepEqual(chunkText("short"), ["short"]);
  });
});

describe("prompt", () => {
  test("includes venue, IANA zone, today's local date + weekday, URL and asks for a list with verbatim evidence", () => {
    const { system, user } = buildEventPrompt({
      venueName: "The Example Room",
      timezone: "America/Chicago",
      now: new Date("2026-11-03T04:30:00Z"), // still Nov 2 in Chicago
      pageUrl: SOURCE.url,
      text: "hello",
    });
    assert.match(user, /Venue: The Example Room/);
    assert.match(user, /Venue timezone \(IANA\): America\/Chicago/);
    assert.match(user, /Today at the venue: Monday 2026-11-02/);
    assert.match(user, /Page URL: https:\/\/example-room\.test\/shows/);
    assert.match(system, /VERBATIM/);
    assert.match(system, /--MM-DD/);
    assert.match(system, /every distinct event/);
  });

  test("schema is strict: every property required, no additional properties", () => {
    const items = (EVENT_LIST_SCHEMA.properties as { events: { items: Record<string, unknown> } }).events.items;
    assert.equal(items.additionalProperties, false);
    assert.deepEqual(
      [...(items.required as string[])].sort(),
      Object.keys(items.properties as Record<string, unknown>).sort(),
    );
  });

  test("parseLlmEvents maps fields and tolerates junk", () => {
    const events = parseLlmEvents(RESPONSE);
    assert.equal(events.length, 7);
    const first = events[0];
    assert.equal(first?.start, "--11-06T20:00");
    assert.equal(first?.doors, "19:00");
    assert.equal(first?.extractor, "llm");
    assert.deepEqual(
      first?.prices.map((p) => [p.kind, p.minCents]),
      [
        ["advance", 1500],
        ["door", 2000],
      ],
    );
    assert.equal(events[4]?.status, "sold_out");
    assert.deepEqual(parseLlmEvents({ events: [null, 3, { title: "x", start_date: "next week" }] })[0]?.start, null);
    assert.deepEqual(parseLlmEvents("nope"), []);
  });
});

describe("LLM extraction end to end (fake client) + validation", () => {
  test("hallucinated and evidence-less events are rejected; real ones validated", async () => {
    const llm = new FakeLlm(() => RESPONSE);
    const result = await extractEventsWithLlm(page(), ctx(llm));
    assert.equal(llm.requests.length, 1);
    assert.equal(llm.requests[0]?.schemaName, "venue_events");
    assert.doesNotMatch(llm.requests[0]?.user ?? "", /cookies/);
    assert.equal(result.events.length, 7);
    assert.equal(result.inputTokens, 10);

    const validated = validateEvents(result.events, {
      source: SOURCE,
      venue: { id: "venue-1", name: "The Example Room" },
      timezone: "America/Chicago",
      now: NOW,
      pageText: HTML,
      pageContentType: "text/html",
    });
    const titles = validated.valid.map((e) => e.title);
    assert.deepEqual(titles, [
      "The Example Band w/ Openers & Friends",
      "Late Night DJ Set",
      "Open Mic Night",
      "New Year Jazz Bash",
    ]);
    const reasons = Object.fromEntries(validated.rejected.map((r) => [r.extracted.title, r.reasons.join(",")]));
    assert.equal(reasons["Taylor Swift Secret Show"], "evidence_not_found:1");
    assert.equal(reasons["Phantom Band"], "evidence_missing");
    assert.equal(reasons["Trivia Night"], "category_other:non_event:trivia");

    const [band, dj, mic, jazz] = validated.valid;
    assert.equal(band?.startUtc, "2026-11-07T02:00:00.000Z");
    assert.equal(band?.doorsLocal, "2026-11-06T19:00");
    assert.equal(dj?.endLocal, "2026-11-08T02:00");
    assert.equal(dj?.isFree, true);
    assert.equal(mic?.category, "open_mic");
    assert.equal(jazz?.startLocal, "2027-01-09T21:00");
    assert.equal(jazz?.status, "sold_out");
  });

  test("no LLM configured -> no events, no calls", async () => {
    const result = await extractEventsWithLlm(page(), ctx());
    assert.deepEqual(result.events, []);
  });

  test("chunks are prompted separately and duplicates across overlap merged", async () => {
    const filler = Array.from({ length: 300 }, (_, i) => `<p>Filler paragraph ${i} ${"lorem ".repeat(10)}</p>`).join(
      "",
    );
    const big = HTML.replace("<main>", `<main>${filler}`);
    const llm = new FakeLlm(() => ({ events: [(RESPONSE as { events: unknown[] }).events[0]] }));
    const result = await extractEventsWithLlm(page(big), ctx(llm), { maxChars: 6000, overlapChars: 500 });
    assert.ok(llm.requests.length > 1);
    assert.match(llm.requests[1]?.user ?? "", /part 2 of/);
    assert.equal(result.events.length, 1);
  });
});

describe("OpenAiCompatibleClient", () => {
  type Call = { url: string; init: RequestInit };
  const okBody = (content: unknown, extra: Record<string, unknown> = {}) =>
    new Response(
      JSON.stringify({
        model: "gpt-4o-mini-2024-07-18",
        choices: [{ finish_reason: "stop", message: { content: JSON.stringify(content) }, ...extra }],
        usage: { prompt_tokens: 120, completion_tokens: 30 },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  const request: LlmJsonRequest = { system: "sys", user: "usr", schemaName: "venue_events", schema: EVENT_LIST_SCHEMA };

  test("sends a strict json_schema request and parses the result", async () => {
    const calls: Call[] = [];
    const client = new OpenAiCompatibleClient({
      apiKey: "test-key",
      baseUrl: "https://llm.invalid/v1/",
      fetchImpl: async (url, init) => {
        calls.push({ url: String(url), init: init ?? {} });
        return okBody({ events: [] });
      },
    });
    const response = await client.completeJson(request);
    assert.deepEqual(response, {
      data: { events: [] },
      model: "gpt-4o-mini-2024-07-18",
      inputTokens: 120,
      outputTokens: 30,
    });
    assert.equal(calls[0]?.url, "https://llm.invalid/v1/chat/completions");
    assert.equal((calls[0]?.init.headers as Record<string, string>).authorization, "Bearer test-key");
    const body = JSON.parse(String(calls[0]?.init.body));
    assert.equal(body.model, "gpt-4o-mini");
    assert.equal(body.temperature, 0);
    assert.deepEqual(body.response_format.type, "json_schema");
    assert.equal(body.response_format.json_schema.strict, true);
    assert.equal(body.response_format.json_schema.name, "venue_events");
    assert.equal(body.messages[0].role, "system");
  });

  test("retries 429/5xx, then succeeds", async () => {
    let n = 0;
    const sleeps: number[] = [];
    const client = new OpenAiCompatibleClient({
      apiKey: "k",
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      fetchImpl: async () => (++n < 3 ? new Response("busy", { status: n === 1 ? 429 : 503 }) : okBody({ events: [] })),
    });
    await client.completeJson(request);
    assert.equal(n, 3);
    assert.deepEqual(sleeps, [1000, 4000]);
  });

  test("does not retry 400; surfaces refusals, truncation and invalid JSON; redacts keys", async () => {
    const mk = (res: () => Response) =>
      new OpenAiCompatibleClient({ apiKey: "k", maxRetries: 0, fetchImpl: async () => res() });
    await assert.rejects(
      mk(() => new Response('{"error":"bad key sk-abcdef123"}', { status: 400 })).completeJson(request),
      (e: unknown) => e instanceof LlmError && e.code === "http" && e.status === 400 && !e.message.includes("abcdef"),
    );
    await assert.rejects(
      mk(() => new Response(JSON.stringify({ choices: [{ message: { content: null, refusal: "no" } }] }))).completeJson(
        request,
      ),
      (e: unknown) => e instanceof LlmError && e.code === "refusal",
    );
    await assert.rejects(
      mk(
        () => new Response(JSON.stringify({ choices: [{ finish_reason: "length", message: { content: "{" } }] })),
      ).completeJson(request),
      (e: unknown) => e instanceof LlmError && e.code === "truncated",
    );
    await assert.rejects(
      mk(() => new Response(JSON.stringify({ choices: [{ message: { content: "not json" } }] }))).completeJson(request),
      (e: unknown) => e instanceof LlmError && e.code === "invalid_json",
    );
  });

  test("llmClientFromEnv", () => {
    assert.equal(llmClientFromEnv({}), null);
    const client = llmClientFromEnv({ OPENAI_API_KEY: "k", EVENT_SCRAPER_LLM_MODEL: "gpt-4.1-mini" });
    assert.equal(client?.model, "gpt-4.1-mini");
    assert.equal(llmClientFromEnv({ OPENAI_API_KEY: "k" })?.model, "gpt-4o-mini");
  });
});

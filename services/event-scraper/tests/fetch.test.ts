import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { isPrivateHost, isTicketingUrl, ticketingMatch } from "../src/denylist.js";
import { FetchBlockedError, FetchError, PoliteHttpClient, parseRobots, USER_AGENT } from "../src/fetch.js";
import type { Clock } from "../src/types.js";
import { canonicalUrl, registrableDomain } from "../src/url.js";

const fixture = (path: string) => readFileSync(new URL(`./fixtures/${path}`, import.meta.url), "utf8");

interface Call {
  url: string;
  headers: Record<string, string>;
  at: number;
}

type Handler = (url: URL, headers: Record<string, string>, signal?: AbortSignal) => Response | Promise<Response>;

/** Offline fake of global fetch. Records every call; never touches the network. */
function fakeNetwork(routes: Record<string, Handler>, clock: { t: number }) {
  const calls: Call[] = [];
  const fetchImpl = async (input: string | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input));
    const headers = Object.fromEntries(Object.entries((init?.headers as Record<string, string>) ?? {}));
    calls.push({ url: url.href, headers, at: clock.t });
    assert.equal(init?.redirect, "manual", "client must handle redirects itself");
    const handler = routes[url.href] ?? routes[`${url.origin}${url.pathname}`];
    if (!handler) return new Response("not found", { status: 404 });
    return handler(url, headers, init?.signal ?? undefined);
  };
  return { calls, fetchImpl };
}

function fakeTime(start = Date.UTC(2026, 10, 2, 12)) {
  const state = { t: start };
  const clock: Clock = { now: () => new Date(state.t) };
  const sleeps: number[] = [];
  // Virtual timers: sleepers wake in deadline order and the clock jumps to each deadline, so concurrent
  // waiters observe realistic times. Never uses real timers.
  const timers: { at: number; resolve: () => void }[] = [];
  let pumping = false;
  const pump = () => {
    pumping = false;
    timers.sort((a, b) => a.at - b.at);
    const next = timers.shift();
    if (!next) return;
    state.t = Math.max(state.t, next.at);
    next.resolve();
    if (timers.length) schedule();
  };
  const schedule = () => {
    if (pumping) return;
    pumping = true;
    setImmediate(pump);
  };
  const sleep = (ms: number) =>
    new Promise<void>((resolve) => {
      sleeps.push(ms);
      timers.push({ at: state.t + ms, resolve });
      schedule();
    });
  return { state, clock, sleep, sleeps };
}

const html = (body: string, init: ResponseInit = {}) =>
  new Response(body, { status: 200, headers: { "content-type": "text/html; charset=utf-8" }, ...init });

describe("ticketing denylist", () => {
  test("matches ticketing platforms on any subdomain and TLD variant", () => {
    for (const url of [
      "https://www.ticketmaster.com/event/123",
      "https://concerts.livenation.com/x",
      "https://www.eventbrite.co.uk/e/1",
      "https://www.eventbrite.com/e/1",
      "https://dice.fm/event/abc",
      "https://link.dice.fm/abc",
      "https://www.axs.com/events/1",
      "https://www.seetickets.us/event/1",
      "https://www.ticketweb.com/event/1",
      "https://www.etix.com/ticket/p/1",
      "https://tixr.com/groups/x",
      "https://ticketmaster.ie/",
      "http://WWW.TICKETMASTER.CA/foo",
    ])
      assert.ok(isTicketingUrl(url), url);
    assert.equal(ticketingMatch("https://link.dice.fm/abc"), "dice.fm");
  });

  test("does not flag venue sites that merely mention tickets", () => {
    for (const url of [
      "https://thehifi.com/events",
      "https://www.ticketsandmusic-venue.test/calendar",
      "https://dicey-bar.test/",
      "https://example-room.test/tickets",
      "not a url",
    ])
      assert.equal(isTicketingUrl(url), false, url);
  });

  test("private hosts are blocked", () => {
    assert.ok(isPrivateHost("http://localhost:8080/"));
    assert.ok(isPrivateHost("http://127.0.0.1/"));
    assert.ok(isPrivateHost("http://192.168.1.10/"));
    assert.ok(isPrivateHost("http://10.0.0.1/"));
    assert.ok(isPrivateHost("http://[::1]/"));
    assert.equal(isPrivateHost("https://thehifi.com/"), false);
    assert.equal(isPrivateHost("https://8.8.8.8/"), false);
  });

  test("client refuses ticketing URLs before any request", async () => {
    const time = fakeTime();
    const net = fakeNetwork({}, time.state);
    const client = new PoliteHttpClient({ fetchImpl: net.fetchImpl, clock: time.clock, sleep: time.sleep });
    await assert.rejects(
      client.get({ url: "https://www.ticketmaster.com/event/1" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "ticketing",
    );
    await assert.rejects(
      client.get({ url: "ftp://venue.test/file" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "scheme",
    );
    await assert.rejects(
      client.get({ url: "http://127.0.0.1/admin" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "private_host",
    );
    assert.equal(net.calls.length, 0, "no request was made, not even robots.txt");
  });

  test("redirects into a ticketing platform are blocked at the hop", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/tickets": () =>
          new Response(null, { status: 302, headers: { location: "https://www.eventbrite.com/e/123" } }),
      },
      time.state,
    );
    const client = new PoliteHttpClient({ fetchImpl: net.fetchImpl, clock: time.clock, sleep: time.sleep });
    await assert.rejects(
      client.get({ url: "https://venue.test/tickets" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "ticketing",
    );
    assert.ok(net.calls.every((call) => !call.url.includes("eventbrite")));
  });
});

describe("robots.txt", () => {
  test("parser: specific group overrides *, longest match wins, wildcards and $", () => {
    const policy = parseRobots(fixture("robots/venue.txt"));
    assert.equal(policy.crawlDelayMs, 10_000);
    assert.equal(policy.isAllowed("/calendar"), true);
    assert.equal(policy.isAllowed("/members/"), false);
    assert.equal(policy.isAllowed("/members/profile"), false);
    assert.equal(policy.isAllowed("/members/calendar?month=11"), true);
    assert.equal(policy.isAllowed("/wp-admin/"), true, "our group replaces the * group");

    const generic = parseRobots(fixture("robots/venue.txt"), "SomeOtherBot");
    assert.equal(generic.isAllowed("/wp-admin/options.php"), false);
    assert.equal(generic.isAllowed("/wp-admin/admin-ajax.php"), true);
    assert.equal(generic.isAllowed("/flyers/show.pdf"), false);
    assert.equal(generic.isAllowed("/flyers/show.pdf?x=1"), true);
    assert.equal(generic.isAllowed("/private/thing"), false);
    assert.equal(generic.crawlDelayMs, null);

    const none = parseRobots(fixture("robots/disallow-all.txt"));
    assert.equal(none.isAllowed("/"), false);
    assert.equal(none.isAllowed("/robots.txt"), true);
    assert.equal(parseRobots("User-agent: *\nDisallow:\n").isAllowed("/anything"), true);
  });

  test("client fetches robots once per origin and blocks disallowed paths", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () =>
          new Response(fixture("robots/venue.txt"), { headers: { "content-type": "text/plain" } }),
        "https://venue.test/calendar": () => html(fixture("pages/calendar.html")),
        "https://other.test/robots.txt": () => new Response(fixture("robots/disallow-all.txt")),
      },
      time.state,
    );
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: time.clock,
      sleep: time.sleep,
      minHostIntervalMs: 1000,
    });
    const result = await client.get({ url: "https://venue.test/calendar" });
    assert.equal(result.status, 200);
    await client.get({ url: "https://venue.test/calendar" });
    await assert.rejects(
      client.get({ url: "https://venue.test/members/secret" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "robots",
    );
    await assert.rejects(
      client.get({ url: "https://other.test/events" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "robots",
    );
    assert.equal(net.calls.filter((call) => call.url === "https://venue.test/robots.txt").length, 1);
    assert.equal(await client.robotsAllowed("https://venue.test/members/calendar"), true);
  });

  test("4xx robots means allow; 5xx or network failure means disallow", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://four.test/robots.txt": () => new Response("forbidden", { status: 403 }),
        "https://four.test/events": () => html("<p>ok</p>"),
        "https://five.test/robots.txt": () => new Response("oops", { status: 500 }),
        "https://down.test/robots.txt": () => {
          throw new TypeError("fetch failed");
        },
      },
      time.state,
    );
    const client = new PoliteHttpClient({ fetchImpl: net.fetchImpl, clock: time.clock, sleep: time.sleep });
    assert.equal((await client.get({ url: "https://four.test/events" })).status, 200);
    assert.equal(await client.robotsAllowed("https://five.test/events"), false);
    assert.equal(await client.robotsAllowed("https://down.test/events"), false);
  });
});

describe("HTTP behaviour", () => {
  test("sends identifiable UA and conditional headers; 304 is not-modified", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/calendar": (_url, headers) =>
          headers["if-none-match"] === '"v1"'
            ? new Response(null, { status: 304, headers: { etag: '"v1"' } })
            : html(fixture("pages/calendar.html"), {
                headers: {
                  "content-type": "text/html; charset=utf-8",
                  etag: '"v1"',
                  "last-modified": "Sun, 01 Nov 2026 10:00:00 GMT",
                },
              }),
      },
      time.state,
    );
    const client = new PoliteHttpClient({ fetchImpl: net.fetchImpl, clock: time.clock, sleep: time.sleep });
    const first = await client.get({ url: "https://venue.test/calendar" });
    assert.equal(first.status, 200);
    assert.equal(first.notModified, false);
    assert.equal(first.etag, '"v1"');
    assert.equal(first.lastModified, "Sun, 01 Nov 2026 10:00:00 GMT");
    assert.match(first.text, /Upcoming Shows/);
    assert.equal(first.body.byteLength, Buffer.byteLength(fixture("pages/calendar.html")));
    assert.match(first.sha256, /^[a-f0-9]{64}$/);
    assert.equal(first.contentType, "text/html; charset=utf-8");

    const second = await client.get({
      url: "https://venue.test/calendar",
      etag: first.etag,
      lastModified: first.lastModified,
    });
    assert.equal(second.status, 304);
    assert.equal(second.notModified, true);
    assert.equal(second.body.byteLength, 0);

    const pageCalls = net.calls.filter((call) => call.url === "https://venue.test/calendar");
    assert.equal(pageCalls.length, 2);
    for (const call of [...pageCalls, ...net.calls]) assert.equal(call.headers["user-agent"], USER_AGENT);
    assert.equal(USER_AGENT, "TappedEventScraper/1.0 (+https://tapped.ai)");
    assert.equal(pageCalls[0]?.headers["if-none-match"], undefined);
    assert.equal(pageCalls[1]?.headers["if-none-match"], '"v1"');
    assert.equal(pageCalls[1]?.headers["if-modified-since"], "Sun, 01 Nov 2026 10:00:00 GMT");
  });

  test("follows redirects up to the cap and records the chain", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "http://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "http://venue.test/calendar": () =>
          new Response(null, { status: 301, headers: { location: "https://venue.test/calendar" } }),
        "https://venue.test/calendar": () => new Response(null, { status: 302, headers: { location: "/events/" } }),
        "https://venue.test/events/": () => html("<p>events</p>"),
        "https://venue.test/loop": () => new Response(null, { status: 302, headers: { location: "/loop" } }),
      },
      time.state,
    );
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: time.clock,
      sleep: time.sleep,
      maxRedirects: 3,
    });
    const result = await client.get({ url: "http://venue.test/calendar" });
    assert.equal(result.finalUrl, "https://venue.test/events/");
    assert.deepEqual(result.redirectChain, [
      "http://venue.test/calendar",
      "https://venue.test/calendar",
      "https://venue.test/events/",
    ]);
    await assert.rejects(
      client.get({ url: "https://venue.test/loop" }),
      (error: unknown) => error instanceof FetchError && error.code === "too_many_redirects",
    );
  });

  test("per-host politeness spaces requests and honors Crawl-delay", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://a.test/robots.txt": () => new Response("", { status: 404 }),
        "https://a.test/x": () => html("x"),
        "https://b.test/robots.txt": () => new Response("User-agent: *\nCrawl-delay: 3\n"),
        "https://b.test/x": () => html("x"),
      },
      time.state,
    );
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: time.clock,
      sleep: time.sleep,
      minHostIntervalMs: 1000,
    });
    await Promise.all([await client.get({ url: "https://a.test/x" }), await client.get({ url: "https://a.test/x" })]);
    const aTimes = net.calls.filter((call) => call.url.startsWith("https://a.test/")).map((call) => call.at);
    for (let i = 1; i < aTimes.length; i++)
      assert.ok(aTimes[i]! - aTimes[i - 1]! >= 1000, `a.test spacing ${aTimes[i]! - aTimes[i - 1]!}`);

    await client.get({ url: "https://b.test/x" });
    await client.get({ url: "https://b.test/x" });
    const bPages = net.calls.filter((call) => call.url === "https://b.test/x").map((call) => call.at);
    assert.ok(bPages[1]! - bPages[0]! >= 3000, "crawl-delay respected");
  });

  test("enforces max bytes and timeout", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/big": () => html("x".repeat(2048)),
        "https://venue.test/declared": () =>
          new Response("tiny", { headers: { "content-type": "text/html", "content-length": "999999" } }),
        "https://venue.test/slow": (_url, _headers, signal) =>
          new Promise<Response>((_resolve, reject) => {
            signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
          }),
      },
      time.state,
    );
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: time.clock,
      sleep: time.sleep,
      maxBytes: 1024,
      timeoutMs: 20,
    });
    await assert.rejects(
      client.get({ url: "https://venue.test/big" }),
      (error: unknown) => error instanceof FetchError && error.code === "too_large",
    );
    await assert.rejects(
      client.get({ url: "https://venue.test/declared" }),
      (error: unknown) => error instanceof FetchError && error.code === "too_large",
    );
    await assert.rejects(
      client.get({ url: "https://venue.test/slow" }),
      (error: unknown) => error instanceof FetchError && error.code === "timeout",
    );
  });

  test("non-2xx statuses are returned, and Retry-After delays the host", async () => {
    const time = fakeTime();
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/busy": () => new Response("slow down", { status: 429, headers: { "retry-after": "120" } }),
        "https://venue.test/ok": () => html("ok"),
      },
      time.state,
    );
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: time.clock,
      sleep: time.sleep,
      minHostIntervalMs: 1000,
    });
    const busy = await client.get({ url: "https://venue.test/busy" });
    assert.equal(busy.status, 429);
    const before = time.state.t;
    await client.get({ url: "https://venue.test/ok" });
    assert.ok(time.state.t - before >= 119_000, "waited for Retry-After");
  });

  test("decodes declared charsets", async () => {
    const time = fakeTime();
    const latin1 = new Uint8Array([0x43, 0x61, 0x66, 0xe9]); // "Café" in ISO-8859-1
    const net = fakeNetwork(
      {
        "https://venue.test/robots.txt": () => new Response("", { status: 404 }),
        "https://venue.test/latin": () =>
          new Response(latin1, { headers: { "content-type": "text/html; charset=ISO-8859-1" } }),
      },
      time.state,
    );
    const client = new PoliteHttpClient({ fetchImpl: net.fetchImpl, clock: time.clock, sleep: time.sleep });
    const result = await client.get({ url: "https://venue.test/latin" });
    assert.equal(result.text, "Café");
    assert.deepEqual([...result.body], [...latin1]);
  });
});

test("url helpers", () => {
  assert.equal(registrableDomain("https://tickets.thehifi.com/x"), "thehifi.com");
  assert.equal(registrableDomain("www.venue.co.uk"), "venue.co.uk");
  assert.equal(registrableDomain("thehifi.com"), "thehifi.com");
  assert.equal(canonicalUrl("HTTPS://Venue.TEST/Calendar#frag"), "https://venue.test/Calendar");
  assert.equal(canonicalUrl("mailto:x@y.z"), null);
});

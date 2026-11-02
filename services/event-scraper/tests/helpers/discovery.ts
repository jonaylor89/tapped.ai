/** Offline helpers for discovery tests. Nothing here touches the network. */
import { readFileSync } from "node:fs";
import { PoliteHttpClient } from "../../src/fetch.js";
import type { Clock, FetchLike } from "../../src/types.js";

export const NOW_MS = Date.UTC(2026, 10, 2, 17);
export const fixedClock: Clock = { now: () => new Date(NOW_MS) };

export const fixtureText = (name: string) =>
  readFileSync(new URL(`../fixtures/discovery/${name}`, import.meta.url), "utf8");
export const fixtureJson = <T = unknown>(name: string) => JSON.parse(fixtureText(name)) as T;

export interface RecordedCall {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string | null;
}

export type Route = (call: RecordedCall) => Response | Promise<Response>;

/** Fake global fetch: exact-URL routes (origin+path fallback); robots.txt is 404 (allow all) unless routed. */
export function fakeFetch(routes: Record<string, Route | string>, defaultType = "text/html; charset=utf-8") {
  const calls: RecordedCall[] = [];
  const fetchImpl: FetchLike = async (input, init) => {
    const url = new URL(String(input));
    const headers: Record<string, string> = {};
    const rawHeaders = init?.headers;
    const entries =
      rawHeaders instanceof Headers
        ? [...rawHeaders.entries()]
        : Object.entries((rawHeaders as Record<string, string>) ?? {});
    for (const [k, v] of entries) headers[k.toLowerCase()] = v;
    const call: RecordedCall = {
      url: url.href,
      method: init?.method ?? "GET",
      headers,
      body: typeof init?.body === "string" ? init.body : null,
    };
    calls.push(call);
    const route = routes[url.href] ?? routes[`${url.origin}${url.pathname}`];
    if (route === undefined) return new Response("not found", { status: 404 });
    if (typeof route === "string")
      return new Response(route, { status: 200, headers: { "content-type": defaultType } });
    return route(call);
  };
  return { calls, fetchImpl };
}

/** The real polite client over a fake network (no politeness delays, robots honored). */
export function politeClient(fetchImpl: FetchLike) {
  return new PoliteHttpClient({ fetchImpl, clock: fixedClock, sleep: async () => {}, minHostIntervalMs: 0 });
}

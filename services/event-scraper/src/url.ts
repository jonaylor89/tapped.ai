/** Small URL helpers. No public-suffix dependency: a short list of common multi-label suffixes is enough here. */

const MULTI_LABEL_SUFFIXES = new Set([
  "co.uk",
  "org.uk",
  "ac.uk",
  "gov.uk",
  "me.uk",
  "ltd.uk",
  "plc.uk",
  "com.au",
  "net.au",
  "org.au",
  "co.nz",
  "org.nz",
  "co.jp",
  "co.za",
  "com.br",
  "com.mx",
  "com.ar",
  "co.in",
  "com.sg",
  "com.hk",
  "co.kr",
  "com.tr",
  "com.cn",
  "co.il",
]);

/** Parses http(s) URLs, adding https:// to bare hosts. Returns null for anything else. */
export function parseHttpUrl(value: string | URL): URL | null {
  try {
    const raw = typeof value === "string" ? value.trim() : value.href;
    const hasScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
    // "mailto:x", "tel:..." etc. are other schemes; "host:8080/path" is a bare host with a port.
    if (!hasScheme && /^[a-z][a-z0-9+.-]*:(?!\d)/i.test(raw)) return null;
    const url = new URL(hasScheme ? raw : `https://${raw}`);
    return url.protocol === "http:" || url.protocol === "https:" ? url : null;
  } catch {
    return null;
  }
}

/** Lower-cased hostname without a trailing dot or leading "www.". */
export function normalizedHost(url: string | URL): string | null {
  const parsed = parseHttpUrl(url);
  if (!parsed) return null;
  return parsed.hostname
    .toLowerCase()
    .replace(/\.$/, "")
    .replace(/^www\./, "");
}

/** Approximate registrable domain ("eTLD+1"), e.g. "tickets.thehifi.com" -> "thehifi.com". */
export function registrableDomain(urlOrHost: string | URL): string | null {
  const host =
    typeof urlOrHost === "string" && !urlOrHost.includes("/") && !urlOrHost.includes(":")
      ? urlOrHost.toLowerCase().replace(/\.$/, "")
      : normalizedHost(urlOrHost);
  if (!host) return null;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host) || host.includes(":")) return host;
  const labels = host.split(".").filter(Boolean);
  if (labels.length <= 2) return labels.join(".");
  const lastTwo = labels.slice(-2).join(".");
  if (MULTI_LABEL_SUFFIXES.has(lastTwo)) return labels.slice(-3).join(".");
  return lastTwo;
}

/** Canonical form for storing/comparing URLs: lower-case host, no fragment, default ports dropped. */
export function canonicalUrl(value: string | URL): string | null {
  const url = parseHttpUrl(value);
  if (!url) return null;
  url.hash = "";
  url.hostname = url.hostname.toLowerCase();
  return url.href;
}

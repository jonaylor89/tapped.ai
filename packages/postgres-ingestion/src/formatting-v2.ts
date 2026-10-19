import type { NormalizedFacts, ScrapedInput } from "./observations";

export type InputPriceUnit = "usd_major" | "usd_cent";
export type PriceCents = {
  kind: "ticket" | "door" | "other";
  amountMinCents: number | null;
  amountMaxCents: number | null;
  currency: "USD";
  description: string | null;
};
export type NormalizedFactsV2 = Omit<NormalizedFacts, "prices"> & { priceUnit: "usd_cent"; prices: PriceCents[] };
export const MAX_PRICE_CENTS = 1_000_000_000_000;
const PLACEHOLDERS = new Set([
  "",
  "n/a",
  "na",
  "none",
  "null",
  "undefined",
  "unknown",
  "not available",
  "not found",
  "no image",
  "no image available",
]);

/** Exact decimal conversion, never floating point multiplication or implicit cent rounding. */
export function usdCents(value: unknown, unit: InputPriceUnit): number | null {
  if (unit !== "usd_major" && unit !== "usd_cent") throw new Error("Explicit input price unit is required");
  if (value == null) return null;
  if (typeof value !== "number" && typeof value !== "string") throw new Error("Invalid price");
  if (typeof value === "number" && (!Number.isFinite(value) || value < 0)) throw new Error("Invalid price");
  const input = typeof value === "string" ? value.trim() : String(value);
  if (input.length > 100 || (typeof value === "string" && !/^\d+(?:\.\d+)?$/.test(input)))
    throw new Error("Invalid price");
  const match = /^(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/i.exec(input);
  if (!match) throw new Error("Invalid price");
  const scale = (match[2]?.length ?? 0) - Number(match[3] ?? 0);
  const power = (unit === "usd_major" ? 2 : 0) - scale;
  const digits = BigInt(match[1] + (match[2] ?? ""));
  let cents: bigint;
  if (power >= 0) {
    if (power > 20) throw new Error("Invalid price");
    cents = digits * 10n ** BigInt(power);
  } else {
    if (power < -400) throw new Error("Invalid price");
    const divisor = 10n ** BigInt(-power);
    if (digits % divisor !== 0n) throw new Error("Fractional cent");
    cents = digits / divisor;
  }
  if (cents >= BigInt(MAX_PRICE_CENTS)) throw new Error("Invalid price");
  return Number(cents);
}

/** Approved, narrow cleanup. The original extraction/evidence is never changed. */
export function formatExtractionV2(data: ScrapedInput, unit: InputPriceUnit) {
  if (unit !== "usd_major" && unit !== "usd_cent") throw new Error("Explicit input price unit is required");
  if (data.priceUnit != null && data.priceUnit !== unit) throw new Error("Input price unit mismatch");
  const { ticketPrice, doorPrice, prices: rawPrices, currency: rawCurrency, ...cleaned } = data;
  const notes: string[] = [];
  const errors: string[] = [];
  const lineup = data.performers ?? data.artists;
  if (Array.isArray(lineup) && lineup.length <= 100) {
    const performers = lineup.filter((entry) => typeof entry !== "string" || entry.trim().length > 0);
    cleaned.performers = performers;
    if (performers.length !== lineup.length) notes.push("empty_performer_omitted");
  }
  for (const field of ["url", "flierUrl"] as const) {
    const value = data[field];
    if (typeof value === "string" && PLACEHOLDERS.has(value.trim().toLowerCase())) {
      cleaned[field] = null;
      if (value !== "") notes.push(`${field}_placeholder_omitted`);
    }
  }
  const currency = (value: unknown): "USD" => {
    if (value == null || (typeof value === "string" && !value.trim())) notes.push("usd_assumed");
    else if (typeof value !== "string" || value.trim().toUpperCase() !== "USD") errors.push("unsupported_currency");
    return "USD";
  };
  const amount = (value: unknown): number | null => {
    try {
      return usdCents(value, unit);
    } catch (error) {
      errors.push(error instanceof Error && error.message === "Fractional cent" ? "fractional_cent" : "invalid_price");
      return null;
    }
  };
  const prices: PriceCents[] = [];
  for (const [value, kind] of [
    [ticketPrice, "ticket"],
    [doorPrice, "door"],
  ] as const) {
    if (value != null) {
      const cents = amount(value);
      prices.push({
        kind,
        amountMinCents: cents,
        amountMaxCents: cents,
        currency: currency(rawCurrency),
        description: null,
      });
    }
  }
  if (rawPrices != null) {
    if (!Array.isArray(rawPrices) || rawPrices.length > 100) errors.push("invalid_prices");
    else {
      prices.length = 0;
      for (const raw of rawPrices) {
        const price = raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as ScrapedInput) : {};
        const hasCents = "amountMinCents" in price || "amountMaxCents" in price;
        if (hasCents && (unit !== "usd_cent" || "amountMin" in price || "amountMax" in price))
          throw new Error("Input price unit mismatch");
        const min = amount(hasCents ? price.amountMinCents : price.amountMin);
        const max = amount(hasCents ? price.amountMaxCents : price.amountMax);
        if (min !== null && max !== null && min > max) errors.push("invalid_price_range");
        if (!["ticket", "door", "other"].includes(String(price.kind))) errors.push("invalid_price_kind");
        prices.push({
          kind: price.kind === "ticket" || price.kind === "door" ? price.kind : "other",
          amountMinCents: min,
          amountMaxCents: max,
          currency: currency(price.currency ?? rawCurrency),
          description: typeof price.description === "string" && price.description.trim() ? price.description : null,
        });
      }
    }
  }
  if (prices.length) notes.push(unit === "usd_major" ? "usd_major_to_cents" : "usd_cents_preserved");
  return { data: cleaned, prices, errors, notes: [...new Set(notes)] };
}

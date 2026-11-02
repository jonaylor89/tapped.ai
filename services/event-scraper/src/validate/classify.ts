import type { EventCategory } from "../types.js";

/**
 * Keyword classifier: music / comedy / open_mic / theater / dance / other, plus non-event detection.
 *
 * Venue calendars mostly list bare performer names ("The Mountain Goats w/ Lydia Loveless") with no genre words, so
 * when nothing points elsewhere we fall back to the extractor hint and then to `defaultCategory` (music, because
 * sources are live-music venues). Non-events (private events, closures, trivia, brunch, karaoke, ...) are always
 * classified "other" and dropped, except karaoke/jam nights that are explicitly open mics.
 */

export interface ClassifyInput {
  title: string;
  description?: string | null;
  performers?: string[];
  /** Extractor's category hint. */
  hint?: EventCategory | null;
  /** Category when no signal at all is present. Default "music". */
  defaultCategory?: EventCategory;
  /** The venue's name; removed from the title before keyword matching ("... at the Ryman Theater"). */
  venueName?: string | null;
}

export interface Classification {
  category: EventCategory;
  isMusic: boolean;
  /** Short machine reason, e.g. "keyword:comedy", "non_event:trivia", "hint", "default". */
  reason: string;
}

const OPEN_MIC =
  /\bopen[\s-]?mi(c|ke)s?\b|\bopen[\s-]?stage\b|\bsong ?writers? (night|round|circle) open\b|\bopen jam\b/i;

/**
 * Category words are split in two tiers. Unambiguous phrases decide the category even against a structured hint;
 * loose words ("theater", "musical", "laughs") only count after the hint and after music words, because they show up
 * in venue names and band names ("... at the Ryman Theater", "Fair Play", "Comic Book Heroes").
 */
const COMEDY_STRONG =
  /\b(comedy|comedian|comedians|stand[\s-]?up( comedy| comic)?|improv( comedy| show| night)?|improvised comedy|sketch comedy|roast battle)\b/i;
const COMEDY_LOOSE = /\b(comedic|roast|funniest|laughs?|humou?r(ist)?)\b/i;

const THEATER_STRONG =
  /\b(the musical|a musical|a new musical|a play|stage play|new play|broadway|off[\s-]broadway|playwright|staged reading|one[\s-](wo)?man show|opera|operetta|burlesque|drag show)\b/i;
const THEATER_LOOSE = /\b(theat(er|re)|musical|drama|cabaret|performance art|puppet(ry)?|variety show)\b/i;

const DANCE_STRONG =
  /\b(ballet|dance (company|performance|recital|theat(er|re)|showcase|troupe)|milonga|swing dance|contra dance|square dance|line dancing|tap dance|modern dance|contemporary dance|hip[\s-]?hop dance|belly ?danc\w*|folk dance)\b/i;
const DANCE_LOOSE = /\b(tango|salsa|bachata|swing night|lindy|ballroom dancing|flamenco)\b/i;

const MUSIC =
  /\b(live music|live band|band|bands|concert|tour|dj|djs|dj set|jazz|blues|rock|punk|metal|hardcore|emo|indie|folk|bluegrass|country|americana|hip[\s-]?hop|rap|r&b|rnb|soul|funk|reggae|ska|edm|house music|techno|electronic|orchestra|symphony|philharmonic|quartet|quintet|trio|choir|chorale|singer|songwriter|acoustic|unplugged|album release|record release|ep release|residency|headlin\w*|support(ing)? act|special guests?|w\/|feat\.?|featuring|tribute|cover band|recital|jam session|jam night|gig|showcase|sessions?|piano|guitar|fiddle|banjo|gospel|karaoke band|live (at|from)|in concert|songs?|set)\b/i;

/** Clear music signals that override soft non-event words ("Happy Hour Jazz Trio", "Poker Face: Gaga Tribute"). */
const CLEAR_MUSIC =
  /\b(live music|live band|band|concert|dj set|jazz|blues|bluegrass|funk|soul|orchestra|symphony|quartet|quintet|trio|tribute|cover band|album release|record release|in concert|singer[\s-]?songwriter)\b/i;

/** Non-events and non-performance events that are dropped. */
const NON_EVENTS: Array<[string, RegExp]> = [
  [
    "private_event",
    /\b(private (event|party|function|booking|rental)|closed (to the public|for (a )?private)|buyout|rental)\b/i,
  ],
  [
    "closure",
    /^(closed\b|we('| a)?re closed|venue closed|bar closed)|\b(closed (today|tonight|for (the )?(holiday|season|thanksgiving|christmas|new year))|holiday hours|no (show|music|events?) (tonight|today))\b/i,
  ],
  ["trivia", /\b(trivia|quiz(zo)? night|pub quiz)\b/i],
  ["brunch", /\bbrunch\b/i],
  ["karaoke", /\bkaraoke\b/i],
  ["bingo", /\bbingo\b/i],
  [
    "watch_party",
    /\b(watch party|viewing party|watch along|game day|super bowl|monday night football|nfl|nba finals|world series|march madness|fight night)\b/i,
  ],
  ["happy_hour", /\bhappy hour\b/i],
  [
    "food_drink",
    /\b(wine tasting|beer tasting|tap takeover|pint night|taco tuesday|wing night|dinner special|food trucks?|crawfish boil|oyster (night|roast|special|bar)|raw bar)\b/i,
  ],
  ["market", /\b(market|flea|craft fair|makers fair|vendor fair|pop[\s-]?up shop|record fair|bazaar)\b/i],
  [
    "class",
    /\b(yoga|pilates|fitness|bootcamp|workout|paint (and|&|n) sip|sip (and|&|n) paint|book club|meet[\s-]?up|networking|seminar|lecture|webinar|meeting)\b/i,
  ],
  [
    "kids_family",
    /\b(toddlers?|toddler time|story ?time|kids'? (day|club|camp|crafts?|program)|children'?s (program|activit(y|ies)|hour)|family (day|fun day))\b/i,
  ],
  [
    "tour_outdoors",
    /\b(guided(?: [\w'-]+){0,3} tours?|walking tours?|garden tours?|house tours?|mansion tours?|ghost tours?|trail trek|night hike|hikes?|nature walk|animal encounters?|bird ?walk)\b/i,
  ],
  ["workshop", /\b(workshops?|classes|masterclass|crash course|tutorial)\b/i],
  [
    "talk",
    /\b(talks?|author (talk|reading|signing)|book (signing|launch|reading)|story club|reading series|panel discussion)\b/i,
  ],
  ["photo_session", /\bphoto (sessions?|shoots?|ops?)\b/i],
  ["screening", /\b(film screening|movie (night|screening)|screening of|screenings?)\b/i],
  ["exhibit", /\b(exhibit(ion)?s?|gallery opening|art opening|art walk)\b/i],
  [
    "games",
    /\b(game night|board games|poker (night|tournament|league)|bingo|cornhole|darts league|pool tournament|trivia)\b/i,
  ],
];

const NON_EVENT_UNLESS_OPEN_MIC = new Set(["karaoke"]);
/** Non-event reasons that never apply to a title with a clear music signal (or a structured music hint). */
const SOFT_NON_EVENTS = new Set([
  "brunch",
  "happy_hour",
  "food_drink",
  "market",
  "class",
  "games",
  "kids_family",
  "tour_outdoors",
  "workshop",
  "talk",
  "photo_session",
  "screening",
  "exhibit",
]);

function joined(input: ClassifyInput): string {
  return [input.title, input.performers?.join(" ") ?? ""].join(" \n ");
}

/**
 * Removes the venue's own name and trailing "at/@ the X Theater/Hall" phrases from a title, so venue words never
 * decide the category ("Jason Isbell at the Ryman Theater" is a concert).
 */
export function stripVenueWords(title: string, venueName?: string | null): string {
  let out = title;
  if (venueName && venueName.trim().length >= 3) {
    const escaped = venueName
      .trim()
      .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      .replace(/^the\s+/i, "");
    out = out.replace(new RegExp(`(?:\\bthe\\s+)?${escaped}`, "gi"), " ");
  }
  out = out
    .replace(
      /(?:^|\s)(?:@|at)\s+(?:the\s+)?[^,|:;()]{0,60}?\b(theat(?:er|re)s?|opera house|playhouse|music hall|ballroom|auditorium)\b/gi,
      " ",
    )
    .replace(/^[^:]{0,60}?\b(theat(?:er|re)|playhouse|ballroom)\s+presents?\s*:?\s*/i, " ");
  return out.replace(/\s+/g, " ").trim() || title;
}

export function detectNonEvent(input: ClassifyInput): string | null {
  // Non-event detection looks at the title only: descriptions often mention "brunch menu" or "happy hour" in passing.
  const title = stripVenueWords(input.title, input.venueName);
  const openMic = OPEN_MIC.test(title);
  const clearMusic = input.hint === "music" || CLEAR_MUSIC.test(title);
  for (const [reason, re] of NON_EVENTS) {
    if (!re.test(title)) continue;
    if (NON_EVENT_UNLESS_OPEN_MIC.has(reason) && openMic) continue;
    if (SOFT_NON_EVENTS.has(reason) && clearMusic) continue;
    // "Jazz Brunch" / "Bluegrass Brunch" with live music is still a music event.
    if (reason === "brunch" && /\b(live|jazz|gospel|bluegrass|band|music)\b/i.test(title)) continue;
    // A watch party of a band's livestream etc. is rare; keep the rule strict.
    return reason;
  }
  return null;
}

export function classifyEvent(input: ClassifyInput): Classification {
  const nonEvent = detectNonEvent(input);
  if (nonEvent) return { category: "other", isMusic: false, reason: `non_event:${nonEvent}` };

  const title = joined({ ...input, title: stripVenueWords(input.title, input.venueName) });
  const description = input.description ?? "";
  const all = `${title}\n${description}`;

  // 1. Unambiguous title phrases.
  if (OPEN_MIC.test(title)) return result("open_mic", "keyword:open_mic", all);
  for (const [category, re] of STRONG) if (re.test(title)) return result(category, `keyword:${category}`, all);
  // 2. The extractor's hint (structured data types like MusicEvent/ComedyEvent, or the LLM's judgement).
  if (input.hint && input.hint !== "other") return result(input.hint, "hint", all);
  // 3. Music words in the title, then loose category words, then the description.
  if (MUSIC.test(title)) return result("music", "keyword:music", all);
  for (const [category, re] of LOOSE) if (re.test(title)) return result(category, `keyword:${category}`, all);
  if (OPEN_MIC.test(description)) return result("open_mic", "description:open_mic", all);
  for (const [category, re] of [...STRONG, ...LOOSE])
    if (re.test(description)) return result(category, `description:${category}`, all);
  if (MUSIC.test(description)) return result("music", "description:music", all);
  // 4. No signal.
  if (input.hint === "other") return { category: "other", isMusic: false, reason: "hint" };
  return result(input.defaultCategory ?? "music", "default", all);
}

/** Unambiguous phrases, checked before the hint and before (broad) music words. */
const STRONG: Array<[EventCategory, RegExp]> = [
  ["comedy", COMEDY_STRONG],
  ["theater", THEATER_STRONG],
  ["dance", DANCE_STRONG],
];
/** Loose words, checked after the hint and after music words. */
const LOOSE: Array<[EventCategory, RegExp]> = [
  ["comedy", COMEDY_LOOSE],
  ["theater", THEATER_LOOSE],
  ["dance", DANCE_LOOSE],
];

const LIVE_MUSIC = /\b(live music|live band|band|concert|dj|djs|orchestra|jazz|blues|bluegrass)\b/i;

function result(category: EventCategory, reason: string, text: string): Classification {
  if (category === "other") return { category, isMusic: false, reason };
  // Non-music categories can still carry live music ("Salsa night with live band", "Open mic for musicians").
  const isMusic = category === "music" || LIVE_MUSIC.test(text);
  return { category, isMusic, reason };
}

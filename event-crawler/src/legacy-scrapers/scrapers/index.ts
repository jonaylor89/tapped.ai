// import all scrapers
import type { Scraper } from "../types";
import JungleRoomScraper from "./jungleroom";
import GoldenPony from "./goldenpony";
import EmberScraper from "./ember";
import WondervilleScraper from "./wonderville";
import PearlStreetScraper from "./pearlstreet";
import SongbyrdScraper from "./songbyrd";
// Additional scrapers (not currently active but available)
// import BrooklynMadeProductionsScraper from "./brooklyn-made-productions";
// import CometOldScraper from "./comet-old";
// import NighthorseScraper from "./nighthorse";
// import OldtownScraper from "./oldtown";

// Currently active scrapers (6 out of 10 total available)
export const scrapers: Scraper[] = [
  JungleRoomScraper,
  EmberScraper,
  GoldenPony,
  WondervilleScraper,
  PearlStreetScraper,
  SongbyrdScraper,
];

// All available scrapers in the directory (for migration reference):
// 1. jungleroom - ✓ Active
// 2. goldenpony - ✓ Active
// 3. ember - ✓ Active
// 4. wonderville - ✓ Active
// 5. pearlstreet - ✓ Active
// 6. songbyrd - ✓ Active
// 7. brooklyn-made-productions - Available but not active
// 8. comet-old - Available but not active
// 9. nighthorse - Available but not active
// 10. oldtown - Available but not active

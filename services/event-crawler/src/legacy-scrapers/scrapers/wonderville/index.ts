import type { Scraper } from "../../types";
import { config } from "./config";
import { scrape } from "./scraper";

const scraper: Scraper = {
  run: scrape,
  config,
};

export default scraper;

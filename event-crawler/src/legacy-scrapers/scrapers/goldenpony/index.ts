import { Scraper } from "../../types";
import { scrape } from "./scraper";
import { config } from "./config";

const scraper: Scraper = {
  run: scrape,
  config,
};

export default scraper;

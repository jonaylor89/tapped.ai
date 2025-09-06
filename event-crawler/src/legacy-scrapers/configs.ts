export const legacyScraperConfigs = [
  {
    id: "DGeZx8VvolPscUOJzFX8cfgE3Rr2",
    name: "jungle-room",
    username: "thejungleroom",
    url: "https://thejungleroomrva.com",
    sitemap: "https://thejungleroomrva.com/sitemap.xml",
    city: "Richmond, Virginia",
  },
  {
    id: "Mleihxk6vIh3LOLR0P03Rjft6vJ2",
    name: "goldenpony",
    username: "goldenpony",
    url: "https://www.goldenponyva.com",
    sitemap: "https://www.goldenponyva.com/sitemap.xml",
    city: "Harrisonburg, Virginia",
  },
  {
    id: "mmV91PvDkYcawkDlhwgUUs4bsl83",
    name: "ember",
    username: "ember_music_hall",
    url: "https://embermusichall.com/",
    sitemap: "https://embermusichall.com/wp-sitemap-posts-rhp_events-1.xml",
    city: "Richmond, Virginia",
  },
  {
    id: "3rpQXXKUi7hy5ZGheeeJcU1S5bK2",
    name: "wonderville",
    username: "wonderville",
    url: "https://www.wonderville.nyc/",
    sitemap: "https://www.wonderville.nyc/sitemap.xml",
    city: "New York City, New York",
  },
  {
    id: "fgq2S5E4tVN3A4zMtoFW0tBLoLi2",
    name: "pearl-street",
    username: "pearl_street_warehouse",
    url: "https://www.pearlstreetwarehouse.com/",
    sitemap: "https://www.pearlstreetwarehouse.com/tm_events-sitemap.xml",
    city: "Washington, DC",
  },
  {
    id: "oH56wniKfvYa95OWTf5WANOxAbj2",
    name: "songbyrd",
    username: "songbyrd_music_house",
    url: "https://songbyrddc.com",
    sitemap: "https://songbyrddc.com/sitemap_index.xml",
    city: "Washington, DC",
  },
  {
    id: "R4FKHwIUMMWZs0xjO9vHqOdN5Wm1",
    name: "brooklynmadepresents",
    username: "brooklyn_made",
    url: "https://brooklynmadepresents.com/",
    sitemap: "https://brooklynmadepresents.com/sitemap_index.xml",
    city: "New York City, N.Y.",
  },
  {
    id: "UT8F6eUeqzbco8LIBxee2RvKNdc2",
    name: "comet-old",
    username: "comet_ping_pong",
    url: "https://www.cometpingpong.com",
    sitemap: "https://www.cometpingpong.com/sitemap.xml",
    city: "Washington, D.C.",
  },
  {
    id: "l8957fA5KIXYIUv31RZGXoF1NI33",
    name: "nighthorse",
    username: "nighthorse",
    url: "https://www.nighthorsebk.com",
    sitemap: "https://www.nighthorsebk.com/sitemap.xml",
    city: "Brooklyn, N.Y.",
  },
  {
    id: "1OTMp6vknsPsYYdwsegiBKil9cC2",
    name: "old-town",
    username: "the_old_town_pub",
    url: "https://otpsteamboat.com/music-events/",
    sitemap: "https://otpsteamboat.com/events-sitemap.xml",
    city: "Steamboat Springs, Colorado",
  },
];

export const LEGACY_SCRAPER_IDS = legacyScraperConfigs.map(
  (config) => config.id,
);

export function getLegacyScraperById(id: string) {
  return legacyScraperConfigs.find((config) => config.id === id);
}

export function getLegacyScraperByUsername(username: string) {
  return legacyScraperConfigs.find((config) => config.username === username);
}

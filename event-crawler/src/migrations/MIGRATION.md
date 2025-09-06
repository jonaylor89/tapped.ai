# Migration from Legacy Webscrapers to Event-Crawler

This document outlines the migration process from the legacy `webscrapers/` project to the unified `event-crawler/` system.

## Overview

The legacy webscrapers used individual, venue-specific scraping logic with Puppeteer, while the event-crawler uses a generalized, LLM-based approach with Crawlee. This migration consolidates all scraping functionality into a single, more maintainable system.

## Key Differences

### Data Structure Changes

**Legacy Schema (webscrapers):**
```typescript
interface ScrapedEventData {
  id: string;
  artists: string[];          // ← Changed to 'performers'
  // ... other fields
}

interface Booking {
  scraperInfo: {              // ← Now 'crawlerInfo'
    scraperId: string;
    runId: string;
  };
  // ... other fields
}
```

**New Schema (event-crawler):**
```typescript
interface EventData {
  eventId: string;
  performers: string[];       // ← Was 'artists'
  crawlerInfo: {              // ← Was 'scraperInfo'
    timestamp: Date;
    runId: string;
    encodedLink: string;
  };
  // ... other fields
}

interface Booking {
  scraperInfo?: {             // ← Kept for backward compatibility
    scraperId: string;
    runId: string;
  } | null;
  crawlerInfo: {              // ← New primary field
    timestamp: Date;
    runId: string;
    encodedLink: string;
  };
  referenceEventId: string | null;  // ← New field
  // ... other fields
}
```

### Storage Changes

**Legacy Storage:**
- Events: `rawScrapeData/{scraperId}/scrapeRuns/{runId}/scrapeResults/{docId}`
- Metadata: `rawScrapeData/{scraperId}`

**New Storage:**
- Events: `crawler/{encodedUrl}`
- No separate metadata collection (venue info stored in user documents)

## Migration Process

### 1. Pre-Migration Setup

Ensure you have the correct Firebase credentials and environment setup:

```bash
cd tapped/event-crawler
cp .env.local.example .env.local
# Edit .env.local with your Firebase credentials
```

### 2. Verify Venue Configuration

Before migration, verify that all venue usernames exist in the database:

```bash
# Verify all legacy venue usernames
npm run verify-venues verify

# Search for specific venues if needed
npm run verify-venues search golden

# List all potential venue accounts
npm run verify-venues list
```

If any venues are missing or have incorrect usernames, update the configurations in `src/legacy-scrapers/configs.ts`.

### 3. Run Migration Script

**Dry Run (Recommended First):**
```bash
cd tapped/event-crawler
npm run build
node dist/migration/migrate-legacy-scrapers.js --dry-run
```

**Full Migration:**
```bash
node dist/migration/migrate-legacy-scrapers.js --force
```

### 4. Legacy Scrapers Included

The following legacy scrapers are migrated:

| Venue | Scraper ID | URL | Location |
|-------|------------|-----|----------|
| Jungle Room | `DGeZx8VvolPscUOJzFX8cfgE3Rr2` | https://thejungleroomrva.com | Richmond, VA |
| Golden Pony | `Mleihxk6vIh3LOLR0P03Rjft6vJ2` | https://www.goldenponyva.com | Harrisonburg, VA |
| Ember Music Hall | `mmV91PvDkYcawkDlhwgUUs4bsl83` | https://embermusichall.com | Richmond, VA |
| Wonderville | `3rpQXXKUi7hy5ZGheeeJcU1S5bK2` | https://www.wonderville.nyc | NYC, NY |
| Pearl Street Warehouse | `fgq2S5E4tVN3A4zMtoFW0tBLoLi2` | https://www.pearlstreetwarehouse.com | Washington, DC |
| Songbyrd | `oH56wniKfvYa95OWTf5WANOxAbj2` | https://songbyrddc.com | Washington, DC |
| Brooklyn Made Presents | `R4FKHwIUMMWZs0xjO9vHqOdN5Wm1` | https://brooklynmadepresents.com | NYC, NY |
| Comet Ping Pong | `UT8F6eUeqzbco8LIBxee2RvKNdc2` | https://www.cometpingpong.com | Washington, DC |
| Nighthorse | `l8957fA5KIXYIUv31RZGXoF1NI33` | https://www.nighthorsebk.com | Brooklyn, NY |
| Old Town Pub | `1OTMp6vknsPsYYdwsegiBKil9cC2` | https://otpsteamboat.com | Steamboat Springs, CO |

### 5. What Gets Migrated

1. **Event Data**: All scraped events from `rawScrapeData` → `crawler`
2. **Bookings**: Updated with new `crawlerInfo` field while preserving `scraperInfo`
3. **Venue Configurations**: Added to event-crawler's venue list

### 6. Post-Migration Verification

After migration, verify the data:

```bash
# Check event count
node -e "
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
db.collection('crawler').get().then(snap => console.log('Events migrated:', snap.size));
"

# Check booking updates
node -e "
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();
db.collection('bookings').where('crawlerInfo', '!=', null).get().then(snap => console.log('Bookings updated:', snap.size));
"
```

### 7. Running the New System

The event-crawler now includes all legacy venues in its crawling rotation:

```bash
cd tapped/event-crawler
npm run start:dev
```

## Rollback Plan

If issues arise, the migration can be partially rolled back:

1. **Events**: Legacy data remains in `rawScrapeData` collection
2. **Bookings**: `scraperInfo` field is preserved for backward compatibility
3. **Legacy System**: Can be reactivated by reverting the `webscrapers/` directory

## Testing

Before running in production:

1. **Dry Run**: Always run migration with `--dry-run` first
2. **Backup**: Ensure Firebase backups are recent
3. **Staging**: Test on a staging environment if available
4. **Monitoring**: Monitor the new crawler for the first few runs

## Troubleshooting

### Common Issues

**Migration Script Fails:**
- Check Firebase credentials
- Verify network connectivity
- Check for rate limiting

**Missing Venues:**
- Run `npm run verify-venues verify` to check venue status
- Ensure venue documents exist in `users` collection
- Check venue IDs match scraper configurations
- Update usernames in `src/legacy-scrapers/configs.ts` if needed

**Booking Updates Fail:**
- Check for booking document permissions
- Verify `scraperInfo.scraperId` matches expected values

### Logs

Migration logs will show:
- Number of events migrated
- Number of bookings updated
- Any errors encountered

## Performance Considerations

The migration processes:
- 10 legacy scrapers
- Potentially thousands of events
- Hundreds of bookings

Expected runtime: 10-45 minutes depending on data volume.

## Next Steps

After successful migration:

1. **Archive Legacy Code**: Move `webscrapers/` to an archive directory
2. **Update CI/CD**: Point deployment to `event-crawler/`
3. **Monitor**: Watch the unified system for a few days
4. **Cleanup**: Remove unused Firebase collections after verification

## Support

For issues during migration:
1. Check logs for specific error messages
2. Verify all prerequisites are met
3. Contact the development team with log excerpts
# Event Crawler - Unified Web Scraping System

A production-ready event crawler built with Crawlee + CheerioCrawler + TypeScript that uses LLM-based parsing to extract event data from venue websites.

This system replaces the legacy individual venue scrapers with a unified, generalized approach that can adapt to different website structures automatically.

## Features

- **LLM-Powered Parsing**: Uses OpenAI to intelligently extract event data from any website structure
- **Venue Management**: Automatically crawls configured venue websites and sitemaps
- **Firebase Integration**: Stores events and creates bookings in Firestore
- **Artist Creation**: Automatically creates artist profiles for performers
- **Booking Generation**: Creates confirmed bookings for music events

## Quick Start

```bash
# Install dependencies
npm install

# Set up environment
cp .env.local.example .env.local
# Edit .env.local with your Firebase credentials and OpenAI API key

# Build the project
npm run build

# Run in development mode
npm run start:dev

# Run in production mode
npm run start:prod
```

## Configuration

Venue configurations are managed in `src/utils/database.ts` in the `getVenueUsernameChunk()` function. Each venue must have:

1. A user document in Firestore with venue information
2. An entry in the venue username list
3. A valid website URL and sitemap

## Architecture

- **Crawlee**: Handles website crawling and sitemap parsing
- **OpenAI**: Extracts structured event data from HTML content
- **Firebase**: Stores events, bookings, and user data
- **TypeScript**: Provides type safety throughout the system

## Data Flow

1. Load venue configurations from database
2. Build domain map for venue websites
3. Crawl venue sitemaps for event pages
4. Use LLM to extract event data from each page
5. Store events in `crawler` collection
6. Create bookings for music events
7. Generate artist profiles for new performers

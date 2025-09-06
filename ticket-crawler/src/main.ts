import { PlaywrightCrawler, Sitemap } from 'crawlee';
import { configDotenv } from "dotenv";
import { router } from './routes.js';
import { getVenueUrls } from './utils/database.js';
configDotenv({
    path: ".env.local",
});


async function main() {
    const venueUrls = await getVenueUrls();

    console.log(`[+] found ${venueUrls.length} venues`);

    const crawler = new PlaywrightCrawler({
        launchContext: {
            // Here you can set options that are passed to the playwright .launch() function.
            launchOptions: {
                headless: true,
            },
        },

        // proxyConfiguration: new ProxyConfiguration({ proxyUrls: ['...'] }),
        requestHandler: router,
        // Comment this option to scrape the full website.
        maxRequestsPerCrawl: 200,
        maxConcurrency: 20,
    });

    for (const url of venueUrls) {
        const sitemapUrl = `${url}/sitemap.xml`;
        const { urls } = await Sitemap.load(sitemapUrl);

        const filteredUrls = urls.filter((url) => {
            const excludedPaths = [
                "/photobooth",
                "format=ical",
            ];

            return !excludedPaths.some((path) => url.includes(path));
        });


        await crawler.addRequests(filteredUrls);
    }

    await crawler.run(venueUrls);
}


main()
    .then(() => console.log("done"))
    .catch(console.error);



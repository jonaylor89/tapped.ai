import { createPlaywrightRouter } from 'crawlee';

export const router = createPlaywrightRouter();

const ticketDomains = [
    "livenation.com",
    "ticketmaster.com/event",
    "eventbrite.com",
    "stubhub.com",
    "seatgeek.com",
    "axs.com",
    "vividseats.com",
    "ticketnetwork.com",
    "ticketsnow.com",
    "ticketcity.com",
    "tickets.com",
    "ticketfly.com",
    "shotgun.live",
    "ticketweb.com",
    "brownpapertickets.com",
    "goldstar.com",
    "gametime.co",
    "ticketliquidator.com",
    "etix.com/ticket/p",
    "facebook.com/events",
    "ticketek.com.au",
];

router.addDefaultHandler(async ({ enqueueLinks, pushData, request, page }) => {
    // find all the links on the page

    const hrefs = await page.locator('a').evaluateAll((as: HTMLAnchorElement[]) => as.map(a => a.href)) as string[];
    // const links = $('[href]')
    //     .map((i, el) => $(el).attr('href'))
    //     .get();

    // filter out the links that are not from ticket domains
    const ticketLinks = hrefs.filter(link => ticketDomains.some(domain => link.includes(domain)));

    if (ticketLinks.length > 0) {
        await pushData({
            loadedUrl: request.loadedUrl,
            ticketLinks,
        });
    }

    await enqueueLinks({
        globs: ["!**/photobooth* !*format=ical*"],
    });
});


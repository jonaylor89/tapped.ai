import { UserModel } from "../types.js";
import { db } from "./firebase.js";

export async function getVenueUrls() {
    const venuesSnap = db
        .collection("users")
        .where("occupations", "array-contains-any", ["venue", "Venue"])
        .where("venueInfo.websiteUrl", "!=", null)
        .get();

    const venues = (await venuesSnap).docs.map((doc) => doc.data() as UserModel);

    const venueWebsites = venues
        .map((venue) => {
            const trimmed = venue.venueInfo?.websiteUrl?.trim()
            if (!trimmed?.startsWith("https://") || !trimmed?.startsWith("http://")) {
                return `https://${trimmed}`;
            }
            return trimmed;
        })
        .filter((url) => {
            if (url === undefined || url === null) {
                return false;
            }

            try {
                // must be a valid URL
                new URL(url);
                return true;
            } catch (e) {
                console.log(`invalid URL: ${url}`)
                return false
            }
        }) as string[];

    return venueWebsites;
}

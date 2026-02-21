import { LRUCache } from "lru-cache";
import { type NextRequest, NextResponse } from "next/server";
import {
	type BoundingBox,
	queryUsers,
	queryVenuesInBoundedBox,
	type UserSearchOptions,
} from "@/data/typesense";
import type { UserModel } from "@/domain/types/user_model";

const userCache = new LRUCache<string, UserModel[]>({
	max: 500,
	ttl: 30 * 1000,
});

const venueCache = new LRUCache<string, UserModel[]>({
	max: 500,
	ttl: 60 * 1000,
});

function buildUserCacheKey(query: string, options: UserSearchOptions): string {
	const lat = options.lat?.toFixed(3) ?? "null";
	const lng = options.lng?.toFixed(3) ?? "null";
	const hitsPerPage = options.hitsPerPage ?? "null";
	return `users:${query}:${lat}:${lng}:${hitsPerPage}`;
}

function buildVenueCacheKey(boundingBox: BoundingBox | null, options: UserSearchOptions): string {
	const neLat = boundingBox?.ne.lat.toFixed(3) ?? "null";
	const neLng = boundingBox?.ne.lng.toFixed(3) ?? "null";
	const swLat = boundingBox?.sw.lat.toFixed(3) ?? "null";
	const swLng = boundingBox?.sw.lng.toFixed(3) ?? "null";
	const hitsPerPage = options.hitsPerPage ?? "null";
	return `venues:${neLat}:${neLng}:${swLat}:${swLng}:${hitsPerPage}`;
}

export async function POST(request: NextRequest) {
	try {
		const body = await request.json();
		const { type, query, boundingBox, options } = body;

		if (!type) {
			return NextResponse.json({ error: "Search type is required" }, { status: 400 });
		}

		if (!options || typeof options !== "object") {
			return NextResponse.json({ error: "Search options are required" }, { status: 400 });
		}

		let results: UserModel[] | null = null;
		switch (type) {
			case "users": {
				if (typeof query !== "string") {
					return NextResponse.json(
						{ error: "Query string is required for user search" },
						{ status: 400 }
					);
				}
				const userCacheKey = buildUserCacheKey(query, options as UserSearchOptions);
				const cachedUsers = userCache.get(userCacheKey);
				if (cachedUsers) {
					results = cachedUsers;
				} else {
					results = await queryUsers(query, options as UserSearchOptions);
					if (results) {
						userCache.set(userCacheKey, results);
					}
				}
				break;
			}

			case "venues": {
				const venueCacheKey = buildVenueCacheKey(
					boundingBox as BoundingBox | null,
					options as UserSearchOptions
				);
				const cachedVenues = venueCache.get(venueCacheKey);
				if (cachedVenues) {
					results = cachedVenues;
				} else {
					results = await queryVenuesInBoundedBox(
						boundingBox as BoundingBox | null,
						options as UserSearchOptions
					);
					if (results) {
						venueCache.set(venueCacheKey, results);
					}
				}
				break;
			}

			default:
				return NextResponse.json(
					{ error: "Invalid search type. Use 'users' or 'venues'" },
					{ status: 400 }
				);
		}

		return NextResponse.json({ results });
	} catch (error) {
		console.error("Search API error:", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}

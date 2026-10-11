import type { BoundingBox } from "@/data/typesense";
import type { UserModel } from "@/domain/types/user_model";
import { type MapBundle, ViewportCache } from "@/lib/map-cache";
import { getCachedUserById, primeMissingPublicProfiles, primePublicProfiles } from "./database";
import { tappedApiUrl } from "./tapped_api";

export type PublicMapBundle = MapBundle<UserModel>;
const cache = new ViewportCache<UserModel>();
function normalize(data: PublicMapBundle, fetchedAt: number): PublicMapBundle {
	primePublicProfiles([...data.venues, ...data.performers], fetchedAt);
	if (!data.performersTruncated) {
		const found = new Set([...data.venues, ...data.performers].map((user) => user.id));
		primeMissingPublicProfiles(
			[...new Set(data.venues.flatMap((venue) => venue.venueInfo?.topPerformerIds ?? []))].filter(
				(id) => !found.has(id)
			),
			fetchedAt
		);
	}
	const rows = (users: UserModel[]) =>
		users.flatMap(({ id }) => {
			const user = getCachedUserById(id);
			return user ? [user] : [];
		});
	return { ...data, venues: rows(data.venues), performers: rows(data.performers) };
}
export function getCachedMapData(bounds: BoundingBox, freshOnly = false) {
	const snapshot = cache.peek(bounds, freshOnly);
	return snapshot ? { ...snapshot, data: normalize(snapshot.data, snapshot.fetchedAt) } : undefined;
}
export async function getMapData(
	bounds: BoundingBox,
	signal?: AbortSignal
): Promise<PublicMapBundle> {
	signal?.throwIfAborted();
	const cached = getCachedMapData(bounds, true);
	if (cached) return cached.data;
	const startedAt = Date.now();
	const params = new URLSearchParams({
		swLat: `${bounds.sw.lat}`,
		swLng: `${bounds.sw.lng}`,
		neLat: `${bounds.ne.lat}`,
		neLng: `${bounds.ne.lng}`,
	});
	const response = await fetch(`${tappedApiUrl}/app/v1/public/map?${params}`, {
		cache: "no-store",
		signal,
	});
	if (!response.ok) throw new Error(`Map data unavailable (${response.status})`);
	const raw = (await response.json()) as PublicMapBundle;
	signal?.throwIfAborted();
	const data = normalize(raw, startedAt);
	cache.put(bounds, data, startedAt);
	return data;
}

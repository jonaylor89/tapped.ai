import { LRUCache } from "lru-cache";
import type { PlaceData, PlacePrediction } from "@/domain/types/place_data";

// Every Places request is billed, so cache the in-flight promise: duplicate calls made while a
// request is pending (re-renders, generateMetadata + Page, repeated searches) share one request.
const placeDetailsCache = new LRUCache<string, Promise<PlaceData>>({
	max: 500,
	ttl: 60 * 60 * 1000,
});
const autocompleteCitiesCache = new LRUCache<string, Promise<PlacePrediction[]>>({
	max: 500,
	ttl: 5 * 60 * 1000,
});

const cachedRequest = <T extends {}>(
	cache: LRUCache<string, Promise<T>>,
	key: string,
	request: () => Promise<T>
): Promise<T> => {
	const cached = cache.get(key);
	if (cached) {
		return cached;
	}

	const promise = request();
	cache.set(key, promise);
	// Don't cache failures.
	promise.catch(() => {
		if (cache.get(key) === promise) {
			cache.delete(key);
		}
	});

	return promise;
};

const normalizeQuery = (q: string) => q.trim().replace(/\s+/g, " ").toLowerCase();

const tappedApiUrl = process.env.NEXT_PUBLIC_TAPPED_API_URL ?? "https://api.tapped.ai";

// The Tapped API caches place details in Firestore `googlePlacesCache`, shared with the apps.
export const getPlaceById = (placeId: string): Promise<PlaceData> =>
	cachedRequest(placeDetailsCache, placeId, async () => {
		const res = await fetch(`${tappedApiUrl}/app/v1/places/${encodeURIComponent(placeId)}`);
		if (!res.ok) {
			throw new Error(`error getting place details for placeId: ${placeId} (${res.status})`);
		}

		return (await res.json()) as PlaceData;
	});

export const autocompleteCities = async (
	q: string,
	types: string[] = ["locality"]
): Promise<PlacePrediction[]> => {
	const query = normalizeQuery(q);
	if (query === "") {
		return [];
	}

	try {
		return await cachedRequest(autocompleteCitiesCache, `${types.join(",")}|${query}`, () =>
			_autocompleteCities(query, types)
		);
	} catch (e) {
		console.error(e);
		return [];
	}
};

const _autocompleteCities = async (q: string, types: string[]): Promise<PlacePrediction[]> => {
	const params = new URLSearchParams({ query: q, types: types.join(",") });
	const res = await fetch(`${tappedApiUrl}/app/v1/places/autocomplete?${params}`);
	if (!res.ok) {
		throw new Error(`error autocompleting places for query: ${q} (${res.status})`);
	}

	return (await res.json()) as PlacePrediction[];
};

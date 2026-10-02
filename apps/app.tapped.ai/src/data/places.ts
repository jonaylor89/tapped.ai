/* eslint-disable @typescript-eslint/no-explicit-any */

import { httpsCallable } from "@firebase/functions";
import { LRUCache } from "lru-cache";
import type { PlaceData } from "@/domain/types/place_data";
import { functions } from "@/utils/firebase";

type CityPrediction = {
	place_id: string;
	description: string;
};

// Every Places request is billed, so cache the in-flight promise: duplicate calls made while a
// request is pending (re-renders, generateMetadata + Page, repeated searches) share one request.
const placeDetailsCache = new LRUCache<string, Promise<PlaceData>>({
	max: 500,
	ttl: 60 * 60 * 1000,
});
const autocompleteCitiesCache = new LRUCache<string, Promise<CityPrediction[]>>({
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
): Promise<CityPrediction[]> => {
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

const _autocompleteCities = async (q: string, types: string[]): Promise<CityPrediction[]> => {
	const callable = httpsCallable(functions, "autocompletePlaces");
	const res = await callable({ query: q, types });
	const data = res.data as {
		predictions: CityPrediction[];
	};

	if ("error_message" in data) {
		console.error({ data });
		throw new Error(String(data.error_message));
	}

	return data.predictions ?? [];
};

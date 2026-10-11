"use client";

import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { getCachedMapData, getMapData, type PublicMapBundle } from "@/data/public_map";
import type { BoundingBox } from "@/data/typesense";
import { speculativeNetworkAllowed } from "@/lib/intent-prefetch";
import {
	bufferedMapBounds,
	MAP_CACHE_LIMIT,
	MAP_FRESH_MS,
	MAP_RETAIN_MS,
	mapBoundsKey,
} from "@/lib/map-cache";

const key = (bounds: BoundingBox | null) =>
	["public-map", bounds ? mapBoundsKey(bounds) : "pending"] as const;
let prefetchTimes: number[] = [];
function prefetchBudget(): boolean {
	prefetchTimes = prefetchTimes.filter((time) => Date.now() - time < 60_000);
	if (prefetchTimes.length >= 6) return false;
	prefetchTimes.push(Date.now());
	return true;
}

export function usePublicMap(bounds: BoundingBox | null) {
	const client = useQueryClient();
	const cached = bounds ? getCachedMapData(bounds) : undefined;
	const query = useQuery({
		queryKey: key(bounds),
		enabled: bounds !== null,
		queryFn: ({ signal }) => {
			if (!bounds) throw new Error("Viewport not ready");
			return getMapData(bounds, signal);
		},
		initialData: cached?.data,
		initialDataUpdatedAt: cached?.fetchedAt,
		placeholderData: keepPreviousData,
		staleTime: MAP_FRESH_MS,
		gcTime: MAP_RETAIN_MS,
		retry: false, // No retry storm on 429; a later settled viewport/refocus may refresh.
	});
	const { data, isFetching, isPlaceholderData } = query;
	const [lastData, setLastData] = useState<PublicMapBundle>();
	useEffect(() => {
		if (data) setLastData(data);
	}, [data]);
	useEffect(() => {
		return client.getQueryCache().subscribe((event) => {
			if (event.type !== "updated") return;
			const entries = client
				.getQueryCache()
				.findAll({ queryKey: ["public-map"] })
				.sort((a, b) => a.state.dataUpdatedAt - b.state.dataUpdatedAt);
			let excess = entries.length - MAP_CACHE_LIMIT;
			for (const entry of entries) {
				if (
					excess > 0 &&
					entry.getObserversCount() === 0 &&
					entry.state.fetchStatus !== "fetching"
				) {
					client.removeQueries({ queryKey: entry.queryKey, exact: true });
					excess--;
				}
			}
		});
	}, [client]);
	useEffect(() => {
		if (
			!bounds ||
			!data ||
			isFetching ||
			isPlaceholderData ||
			data.venuesTruncated ||
			data.performersTruncated ||
			!speculativeNetworkAllowed()
		)
			return;
		// Don't refetch a new buffer after every tiny pan inside the already-warm margin.
		if (getCachedMapData(bufferedMapBounds(bounds, 0.05), true)) return;
		const buffer = bufferedMapBounds(bounds);
		if (mapBoundsKey(buffer) === mapBoundsKey(bounds) || getCachedMapData(buffer, true)) return;
		const queryKey = key(buffer);
		const timer = setTimeout(() => {
			if (!speculativeNetworkAllowed() || !prefetchBudget()) return;
			void client.prefetchQuery({
				queryKey,
				queryFn: ({ signal }) => getMapData(buffer, signal),
				staleTime: MAP_FRESH_MS,
				gcTime: MAP_RETAIN_MS,
				retry: false,
			});
		}, 750);
		return () => {
			clearTimeout(timer);
			// Once a foreground observer takes over, its request must not be cancelled by prefetch cleanup.
			if (!client.getQueryCache().find({ queryKey, exact: true })?.getObserversCount())
				void client.cancelQueries({ queryKey, exact: true });
		};
	}, [bounds, client, data, isFetching, isPlaceholderData]);
	// React Query drops placeholder data on a new viewport's error; keep the last good
	// snapshot instead of blanking the map/sidebar after a 429 or temporary outage.
	return { ...query, data: data ?? lastData };
}

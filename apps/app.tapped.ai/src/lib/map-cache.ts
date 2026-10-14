import type { BoundingBox } from "@/data/search";

export type MapProfile = {
	id: string;
	location?: { lat: number; lng: number } | null;
	venueInfo?: { topPerformerIds?: string[]; genres?: string[] } | null;
};
export type MapBundle<T extends MapProfile> = {
	venues: T[];
	performers: T[];
	genres: Record<string, number>;
	venuesTruncated: boolean;
	performersTruncated: boolean;
};
export const MAP_FRESH_MS = 30_000;
export const MAP_RETAIN_MS = 300_000;
export const MAP_CACHE_LIMIT = 8;

const wrap = (lng: number) => ((((lng + 180) % 360) + 360) % 360) - 180;
const intervals = (bounds: BoundingBox): [number, number][] =>
	bounds.sw.lng <= bounds.ne.lng
		? [[bounds.sw.lng, bounds.ne.lng]]
		: [
				[bounds.sw.lng, 180],
				[-180, bounds.ne.lng],
			];

export function canonicalMapBounds(bounds: BoundingBox): BoundingBox {
	// Round outward, not to nearest: cache-key normalization must not drop boundary venues.
	return {
		sw: {
			lat: Math.max(-90, Math.floor(bounds.sw.lat * 10_000) / 10_000),
			lng: Math.floor(bounds.sw.lng * 10_000) / 10_000,
		},
		ne: {
			lat: Math.min(90, Math.ceil(bounds.ne.lat * 10_000) / 10_000),
			lng: Math.ceil(bounds.ne.lng * 10_000) / 10_000,
		},
	};
}
export function mapBoundsKey(bounds: BoundingBox): string {
	return [bounds.sw.lat, bounds.sw.lng, bounds.ne.lat, bounds.ne.lng].join(",");
}
export function bufferedMapBounds(bounds: BoundingBox, ratio = 0.15): BoundingBox {
	const latPad = (bounds.ne.lat - bounds.sw.lat) * ratio;
	const width =
		bounds.ne.lng >= bounds.sw.lng
			? bounds.ne.lng - bounds.sw.lng
			: bounds.ne.lng + 360 - bounds.sw.lng;
	const wholeWorld = width * (1 + 2 * ratio) >= 360;
	return canonicalMapBounds({
		sw: {
			lat: Math.max(-90, bounds.sw.lat - latPad),
			lng: wholeWorld ? -180 : wrap(bounds.sw.lng - width * ratio),
		},
		ne: {
			lat: Math.min(90, bounds.ne.lat + latPad),
			lng: wholeWorld ? 180 : wrap(bounds.ne.lng + width * ratio),
		},
	});
}
export function containsBounds(outer: BoundingBox, inner: BoundingBox): boolean {
	return (
		outer.sw.lat <= inner.sw.lat &&
		outer.ne.lat >= inner.ne.lat &&
		intervals(inner).every(([west, east]) =>
			intervals(outer).some(([ow, oe]) => ow <= west && oe >= east)
		)
	);
}
export function cropMapBundle<T extends MapProfile>(
	bundle: MapBundle<T>,
	bounds: BoundingBox
): MapBundle<T> {
	const venues = bundle.venues.filter(
		({ location }) =>
			location &&
			location.lat >= bounds.sw.lat &&
			location.lat <= bounds.ne.lat &&
			intervals(bounds).some(([w, e]) => location.lng >= w && location.lng <= e)
	);
	const refs = new Set(venues.flatMap((venue) => venue.venueInfo?.topPerformerIds ?? []));
	const genres: Record<string, number> = {};
	for (const venue of venues)
		for (const genre of venue.venueInfo?.genres ?? []) genres[genre] = (genres[genre] ?? 0) + 1;
	return {
		...bundle,
		venues,
		performers: bundle.performers.filter(({ id }) => refs.has(id)),
		genres,
	};
}

export class ViewportCache<T extends MapProfile> {
	private entries = new Map<
		string,
		{ bounds: BoundingBox; data: MapBundle<T>; fetchedAt: number }
	>();
	constructor(
		private now = Date.now,
		private max = MAP_CACHE_LIMIT
	) {}
	put(bounds: BoundingBox, data: MapBundle<T>, fetchedAt = this.now()) {
		const key = mapBoundsKey(bounds);
		if ((this.entries.get(key)?.fetchedAt ?? 0) > fetchedAt) return;
		this.entries.delete(key);
		this.entries.set(key, { bounds, data, fetchedAt });
		while (this.entries.size > this.max)
			this.entries.delete(this.entries.keys().next().value as string);
	}
	peek(
		bounds: BoundingBox,
		freshOnly = false
	): { data: MapBundle<T>; fetchedAt: number } | undefined {
		const key = mapBoundsKey(bounds);
		for (const [entryKey, entry] of [...this.entries].reverse()) {
			const age = this.now() - entry.fetchedAt;
			if (age >= MAP_RETAIN_MS) {
				this.entries.delete(entryKey);
				continue;
			}
			if (freshOnly && age >= MAP_FRESH_MS) continue;
			const exact = key === entryKey;
			// Capped outer results may have omitted venues/performers from this inner viewport.
			if (
				!exact &&
				(entry.data.venuesTruncated ||
					entry.data.performersTruncated ||
					!containsBounds(entry.bounds, bounds))
			)
				continue;
			this.entries.delete(entryKey);
			this.entries.set(entryKey, entry);
			return {
				data: exact ? entry.data : cropMapBundle(entry.data, bounds),
				fetchedAt: entry.fetchedAt,
			};
		}
		return undefined;
	}
	get size(): number {
		return this.entries.size;
	}
}

// Keep in sync with the API's explicit-ID profile limit. One request at a time, not N per ID.
export const PROFILE_BATCH_SIZE = 50;

export function areaPerformerIds(
	venues: { venueInfo?: { topPerformerIds?: string[] } | null }[]
): string[] {
	return [...new Set(venues.flatMap((venue) => venue.venueInfo?.topPerformerIds ?? []))].sort();
}

export async function batchUsers<T extends { id: string }>(
	ids: string[],
	load: (ids: string[], signal?: AbortSignal) => Promise<T[]>,
	signal?: AbortSignal
): Promise<T[]> {
	const unique = [...new Set(ids)];
	const results = new Map<string, T>();
	for (let offset = 0; offset < unique.length; offset += PROFILE_BATCH_SIZE) {
		signal?.throwIfAborted();
		const chunk = unique.slice(offset, offset + PROFILE_BATCH_SIZE);
		const rows = await load(chunk, signal);
		signal?.throwIfAborted();
		for (const row of rows) {
			if (chunk.includes(row.id)) results.set(row.id, row);
		}
	}
	return unique.flatMap((id) => {
		const row = results.get(id);
		return row ? [row] : [];
	});
}

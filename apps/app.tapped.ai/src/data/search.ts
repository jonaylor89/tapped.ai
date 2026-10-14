// Compatibility exports for existing callers. Search itself is an API/Postgres read.
import type { UserModel } from "@/domain/types/user_model";
import { tappedApiUrl } from "./tapped_api";

export type UserSearchOptions = {
	hitsPerPage: number;
	labels?: string[];
	genres?: string[];
	occupations?: string[];
	occupationsBlacklist?: string[];
	venueGenres?: string[];
	unclaimed?: boolean;
	lat?: number;
	lng?: number;
	radius?: number;
	minCapacity?: number;
	maxCapacity?: number;
};
export type BoundingBox = {
	readonly sw: { lat: number; lng: number };
	readonly ne: { lat: number; lng: number };
};

async function searchUsers(parameters: object): Promise<UserModel[]> {
	try {
		const response = await fetch(`${tappedApiUrl}/app/v1/public/search/users`, {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(parameters),
			cache: "no-store",
		});
		if (!response.ok) throw new Error(`Search unavailable (${response.status})`);
		const users = (await response.json()) as UserModel[];
		return users.map((user) => ({
			...user,
			timestamp: user.timestamp ? new Date(user.timestamp) : undefined,
		}));
	} catch (error) {
		console.error(error);
		return [];
	}
}
export async function queryVenuesInBoundedBox(
	bounds: BoundingBox | null,
	options: UserSearchOptions
): Promise<UserModel[]> {
	return searchUsers({
		...options,
		q: "",
		occupations: ["venue"],
		...(bounds
			? { swLat: bounds.sw.lat, swLng: bounds.sw.lng, neLat: bounds.ne.lat, neLng: bounds.ne.lng }
			: {}),
	});
}
export async function queryUsers(query: string, options: UserSearchOptions): Promise<UserModel[]> {
	return searchUsers({ ...options, q: query });
}

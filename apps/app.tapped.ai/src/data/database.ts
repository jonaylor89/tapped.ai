import { LRUCache } from "lru-cache";
import type { Booking } from "@/domain/types/booking";
import type { Opportunity } from "@/domain/types/opportunity";
import type { Option } from "@/domain/types/option";
import type { Review } from "@/domain/types/review";
import type { UserModel } from "@/domain/types/user_model";
import { batchUsers } from "@/lib/batch-users";
import { createIntentPrefetch, speculativeNetworkAllowed } from "@/lib/intent-prefetch";
import { type PublicBooking, publicBooking } from "@/lib/public-booking";
import { PublicProfileCache } from "@/lib/public-profile-cache";
import { tappedApiUrl } from "./tapped_api";

// Public pages never carry API keys or Firebase admin credentials.
async function read<T>(
	path: string,
	cacheMode: RequestCache = "default",
	signal?: AbortSignal
): Promise<T | null> {
	const response = await fetch(`${tappedApiUrl}/app/v1/${path}`, { cache: cacheMode, signal });
	if (response.status === 404) return null;
	if (!response.ok) throw new Error(`Tapped API request failed (${response.status})`);
	return response.json() as Promise<T>;
}
const id = encodeURIComponent;
const profiles = new PublicProfileCache<UserModel>();
const profileReads = new Map<string, Promise<Option<UserModel>>>();
function userDates(user: UserModel): UserModel {
	return { ...user, timestamp: user.timestamp ? new Date(user.timestamp) : undefined };
}
export function primePublicProfiles(users: UserModel[], fetchedAt = Date.now()): void {
	for (const user of users) profiles.put(userDates(user), fetchedAt);
}
export function primeMissingPublicProfiles(userIds: string[], fetchedAt = Date.now()): void {
	for (const userId of userIds) {
		profiles.missing(userId, fetchedAt);
		if (profiles.getById(userId, true) === null) detailsCache.delete(userId);
	}
}
export function getCachedUserByUsername(username: string): UserModel | null {
	return profiles.getByUsername(username, true) ?? null;
}
export function getCachedUserById(userId: string): UserModel | null {
	return profiles.getById(userId, true) ?? null;
}
async function cachedUser(
	key: string,
	path: string,
	lookup: () => UserModel | null | undefined
): Promise<Option<UserModel>> {
	const cached = lookup();
	if (cached !== undefined) return cached;
	const pending = profileReads.get(key);
	if (pending) return pending;
	const startedAt = Date.now();
	const promise = read<UserModel>(path, "no-store")
		.then((value) => {
			if (!value) {
				if (key.startsWith("id:")) primeMissingPublicProfiles([key.slice(3)], startedAt);
				return null;
			}
			const user = userDates(value);
			profiles.put(user, startedAt);
			return user;
		})
		.finally(() => profileReads.delete(key));
	profileReads.set(key, promise);
	return promise;
}
export function getUserById(userId: string): Promise<Option<UserModel>> {
	return cachedUser(`id:${userId}`, `public/data/users/${id(userId)}`, () =>
		profiles.getById(userId)
	);
}
export function getUsersByIds(userIds: string[], signal?: AbortSignal): Promise<UserModel[]> {
	return batchUsers(
		userIds,
		async (chunk, requestSignal) => {
			const startedAt = Date.now();
			const missing = chunk.filter((userId) => profiles.getById(userId) === undefined);
			const rows = missing.length
				? ((await read<UserModel[]>(
						`public/data/users?ids=${id(missing.join(","))}`,
						"default",
						requestSignal
					)) ?? [])
				: [];
			requestSignal?.throwIfAborted();
			primePublicProfiles(rows, startedAt);
			for (const userId of missing)
				if (!rows.some((row) => row.id === userId)) primeMissingPublicProfiles([userId], startedAt);
			return chunk.flatMap((userId) => {
				const user = profiles.getById(userId);
				return user ? [user] : [];
			});
		},
		signal
	);
}
export function getUserByUsername(username: string): Promise<Option<UserModel>> {
	return cachedUser(`username:${username}`, `users/username/${id(username)}`, () =>
		profiles.getByUsername(username)
	);
}
// Badges and curated leaderboard data were not migrated. Explicitly disabled, no Firestore fallback.
export async function isVerified(_userId: string): Promise<boolean> {
	return false;
}
export async function getFeaturedPerformers(): Promise<UserModel[]> {
	return [];
}
export async function getBookingCount(userId: string): Promise<number> {
	return (await read<number>(`public/users/${id(userId)}/booking-count`)) ?? 0;
}
type ReviewJSON = Omit<Review, "timestamp"> & { timestamp: string };
function reviewDates(review: ReviewJSON): Review {
	return { ...review, timestamp: new Date(review.timestamp) };
}
export async function getLatestPerformerReviewByPerformerId(
	userId: string
): Promise<Option<Review>> {
	const rows = await read<ReviewJSON[]>(
		`public/data/reviews?userId=${id(userId)}&reviewType=performer&limit=1`
	);
	return rows?.[0] ? reviewDates(rows[0]) : null;
}
type OpportunityJSON = Omit<Opportunity, "timestamp" | "startTime" | "endTime" | "deadline"> & {
	timestamp: string;
	startTime: string;
	endTime: string;
	deadline?: string | null;
};
export async function getOpportunityById(opportunityId: string): Promise<Opportunity | null> {
	const value = await read<OpportunityJSON>(`opportunities/${id(opportunityId)}`, "no-store");
	if (!value) return null;
	return {
		...value,
		timestamp: new Date(value.timestamp),
		startTime: new Date(value.startTime),
		endTime: new Date(value.endTime),
		deadline: value.deadline ? new Date(value.deadline) : undefined,
	};
}
export async function getInterestedUsersForOpportunity(opId: string): Promise<UserModel[]> {
	return ((await read<UserModel[]>(`public/opportunities/${id(opId)}/interests`)) ?? []).map(
		userDates
	);
}
export async function getReviewsByPerformerId(userId: string): Promise<Review[]> {
	const results: Review[] = [];
	let after: string | undefined;
	do {
		const page =
			(await read<ReviewJSON[]>(
				`public/data/reviews?userId=${id(userId)}&reviewType=performer&limit=500${after ? `&after=${id(after)}` : ""}`
			)) ?? [];
		results.push(...page.map(reviewDates));
		after = page.length === 500 ? page[page.length - 1].id : undefined;
	} while (after);
	return results;
}
type BookingJSON = Omit<Booking, "timestamp" | "startTime" | "endTime"> & {
	timestamp: string;
	startTime: string;
	endTime: string;
};
async function bookings(
	userId: string,
	role: "requesterId" | "requesteeId",
	limit: number
): Promise<Booking[]> {
	const rows =
		(await read<BookingJSON[]>(
			`public/data/bookings?${role}=${id(userId)}&status=confirmed&order=timestamp&limit=${Math.min(Math.max(limit, 1), 500)}`
		)) ?? [];
	return rows.map((value) => ({
		...value,
		note: "",
		rate: 0,
		timestamp: new Date(value.timestamp),
		startTime: new Date(value.startTime),
		endTime: new Date(value.endTime),
	}));
}
export async function getBookingById(bookingId: string): Promise<PublicBooking | null> {
	const value = await read<Record<string, unknown>>(
		`public/data/bookings/${id(bookingId)}`,
		"no-store"
	);
	return value ? publicBooking(value) : null;
}
export type PublicProfileDetails = {
	user: UserModel;
	bookingCount: number;
	bookings: Booking[];
	latestReview: Review | null;
};
type ProfileDetailsJSON = Omit<PublicProfileDetails, "bookings" | "latestReview"> & {
	bookings: BookingJSON[];
	latestReview: ReviewJSON | null;
	relatedUsers?: UserModel[];
};
const detailsCache = new LRUCache<string, { value: PublicProfileDetails; fetchedAt: number }>({
	max: 100,
	ttl: 300_000,
});
const detailReads = new Map<string, Promise<PublicProfileDetails | null>>();
export function getCachedProfileDetails(userId: string): PublicProfileDetails | null {
	return detailsCache.get(userId)?.value ?? null;
}
export function getPublicProfileDetails(
	userId: string,
	revalidate = false
): Promise<PublicProfileDetails | null> {
	const cached = detailsCache.get(userId);
	if (!revalidate && cached && Date.now() - cached.fetchedAt < 30_000)
		return Promise.resolve(cached.value);
	const pending = detailReads.get(userId);
	if (pending) return pending;
	const startedAt = Date.now();
	const promise = read<ProfileDetailsJSON>(`public/users/${id(userId)}/details`, "no-store")
		.then((row) => {
			if (!row) {
				detailsCache.delete(userId);
				primeMissingPublicProfiles([userId], startedAt);
				return null;
			}
			const value: PublicProfileDetails = {
				user: userDates(row.user),
				bookingCount: row.bookingCount,
				bookings: row.bookings.map((booking) => ({
					...booking,
					note: "",
					rate: 0,
					timestamp: new Date(booking.timestamp),
					startTime: new Date(booking.startTime),
					endTime: new Date(booking.endTime),
				})),
				latestReview: row.latestReview ? reviewDates(row.latestReview) : null,
			};
			const related = row.relatedUsers ?? [];
			primePublicProfiles([value.user, ...related], startedAt);
			if (row.relatedUsers) {
				const found = new Set([value.user.id, ...related.map((user) => user.id)]);
				const tops = value.user.venueInfo?.topPerformerIds;
				const refs = [
					...(Array.isArray(tops) ? tops.slice(0, 20) : []),
					...value.bookings.flatMap((booking) => [booking.requesterId, booking.requesteeId]),
					...(value.latestReview
						? [value.latestReview.bookerId, value.latestReview.performerId]
						: []),
				];
				primeMissingPublicProfiles(
					[
						...new Set(
							refs.filter(
								(ref): ref is string => typeof ref === "string" && ref.length > 0 && !found.has(ref)
							)
						),
					],
					startedAt
				);
			}
			if (profiles.getById(userId, true) === null) return null;
			if ((detailsCache.get(userId)?.fetchedAt ?? 0) <= startedAt)
				detailsCache.set(userId, { value, fetchedAt: startedAt });
			return value;
		})
		.finally(() => detailReads.delete(userId));
	detailReads.set(userId, promise);
	return promise;
}
export const prefetchPublicProfile = createIntentPrefetch(
	(userId) => getPublicProfileDetails(userId),
	speculativeNetworkAllowed
);

export function getBookingsByRequestee(
	userId: string,
	params?: { limit: number }
): Promise<Booking[]> {
	return bookings(userId, "requesteeId", params?.limit ?? 100);
}
export function getBookingsByRequester(
	userId: string,
	params?: { limit: number }
): Promise<Booking[]> {
	return bookings(userId, "requesterId", params?.limit ?? 100);
}

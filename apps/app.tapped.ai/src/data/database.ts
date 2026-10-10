import { LRUCache } from "lru-cache";
import type { Booking } from "@/domain/types/booking";
import type { Opportunity } from "@/domain/types/opportunity";
import type { Option } from "@/domain/types/option";
import type { Review } from "@/domain/types/review";
import type { UserModel } from "@/domain/types/user_model";
import { tappedApiUrl } from "./tapped_api";

// Public pages never carry API keys or Firebase admin credentials.
async function read<T>(path: string): Promise<T | null> {
  const response = await fetch(`${tappedApiUrl}/app/v1/${path}`);
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Tapped API request failed (${response.status})`);
  return response.json() as Promise<T>;
}
const id = encodeURIComponent;
const cache = new LRUCache<string, UserModel>({ max: 500, ttl: 60_000 });
function userDates(user: UserModel): UserModel {
  return { ...user, timestamp: user.timestamp ? new Date(user.timestamp) : undefined };
}
async function cachedUser(key: string, path: string): Promise<Option<UserModel>> {
  const cached = cache.get(key);
  if (cached) return cached;
  const value = await read<UserModel>(path);
  if (!value) return null;
  const user = userDates(value);
  cache.set(key, user);
  return user;
}
export function getUserById(userId: string): Promise<Option<UserModel>> {
  return cachedUser(`id:${userId}`, `public/data/users/${id(userId)}`);
}
export function getUserByUsername(username: string): Promise<Option<UserModel>> {
  return cachedUser(`username:${username}`, `users/username/${id(username)}`);
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
export async function getLatestPerformerReviewByPerformerId(userId: string): Promise<Option<Review>> {
  const rows = await read<ReviewJSON[]>(`public/data/reviews?userId=${id(userId)}&reviewType=performer&limit=1`);
  return rows?.[0] ? reviewDates(rows[0]) : null;
}
type OpportunityJSON = Omit<Opportunity, "timestamp" | "startTime" | "endTime" | "deadline"> & {
  timestamp: string;
  startTime: string;
  endTime: string;
  deadline?: string | null;
};
export async function getOpportunityById(opportunityId: string): Promise<Opportunity | null> {
  const value = await read<OpportunityJSON>(`opportunities/${id(opportunityId)}`);
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
  return ((await read<UserModel[]>(`public/opportunities/${id(opId)}/interests`)) ?? []).map(userDates);
}
export async function getReviewsByPerformerId(userId: string): Promise<Review[]> {
  const results: Review[] = [];
  let after: string | undefined;
  do {
    const page =
      (await read<ReviewJSON[]>(
        `public/data/reviews?userId=${id(userId)}&reviewType=performer&limit=500${after ? `&after=${id(after)}` : ""}`,
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
async function bookings(userId: string, role: "requesterId" | "requesteeId", limit: number): Promise<Booking[]> {
  const rows =
    (await read<BookingJSON[]>(
      `public/data/bookings?${role}=${id(userId)}&status=confirmed&order=timestamp&limit=${Math.min(Math.max(limit, 1), 500)}`,
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
export function getBookingsByRequestee(userId: string, params?: { limit: number }): Promise<Booking[]> {
  return bookings(userId, "requesteeId", params?.limit ?? 100);
}
export function getBookingsByRequester(userId: string, params?: { limit: number }): Promise<Booking[]> {
  return bookings(userId, "requesterId", params?.limit ?? 100);
}

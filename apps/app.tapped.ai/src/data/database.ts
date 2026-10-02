import {
	collection,
	count,
	doc,
	getAggregateFromServer,
	getDoc,
	getDocs,
	limit,
	orderBy,
	query,
	where,
} from "firebase/firestore";
import { LRUCache } from "lru-cache";
import { type Booking, bookingConverter } from "@/domain/types/booking";

import { type Opportunity, opportunityConverter } from "@/domain/types/opportunity";
import type { Option } from "@/domain/types/option";

import { type Review, reviewConverter } from "@/domain/types/review";

import type { UserModel } from "@/domain/types/user_model";
import { db } from "@/utils/firebase";

const verifiedBadgeId = "0aa46576-1fbe-4312-8b69-e2fef3269083";

const userByIdCache = new LRUCache<string, UserModel>({
	max: 500,
});
export async function getUserById(userId: string): Promise<Option<UserModel>> {
	const cached = userByIdCache.get(userId);
	if (cached !== undefined) {
		return cached;
	}

	const docRef = doc(db, "users", userId);
	const docSnap = await getDoc(docRef);
	if (!docSnap.exists()) {
		console.log("user doesnt exist");
		return null;
	}

	const user = docSnap.data() as UserModel;
	userByIdCache.set(userId, user);

	return user;
}

const userByUsernameCache = new LRUCache<string, UserModel>({
	max: 500,
});
export async function getUserByUsername(username: string): Promise<Option<UserModel>> {
	const cached = userByUsernameCache.get(username);
	if (cached !== undefined) {
		return cached;
	}

	const usersCollection = collection(db, "users");
	const q = query(usersCollection, where("username", "==", username), limit(1));

	const querySnapshot = await getDocs(q);
	if (querySnapshot.empty) {
		console.log("no user found!");
		return null;
	}

	const user = querySnapshot.docs[0].data() as UserModel;
	userByUsernameCache.set(username, user);

	return user;
}

const verifiedCache = new LRUCache<string, boolean>({
	max: 500,
});
export async function isVerified(userId: string): Promise<boolean> {
	try {
		const cached = verifiedCache.get(userId);
		if (cached !== undefined) {
			return cached;
		}

		const badgesSentRef = collection(db, "badgesSent");

		const verifiedBadgeSentDoc = await getDoc(
			doc(badgesSentRef, userId, "badges", verifiedBadgeId)
		);

		const verified = verifiedBadgeSentDoc.exists();
		verifiedCache.set(userId, verified);

		return verified;
	} catch (e) {
		console.error(e);
		return false;
	}
}

export async function getBookingCount(userId: string) {
	const bookingQuery = query(collection(db, "bookings"), where("requesteeId", "==", userId));
	const aggr = await getAggregateFromServer(bookingQuery, {
		bookingCount: count(),
	});

	const data = aggr.data();

	return data.bookingCount;
}

export async function getLatestPerformerReviewByPerformerId(
	userId: string
): Promise<Option<Review>> {
	const reviewsCollection = collection(db, `reviews/${userId}/performerReviews`);
	const querySnapshot = query(
		reviewsCollection,
		orderBy("timestamp", "desc"),
		limit(1)
	).withConverter(reviewConverter);

	const queryDocs = await getDocs(querySnapshot);

	if (queryDocs.empty) {
		console.log("No review found!");
		return null;
	}

	return queryDocs.docs[0].data();
}

export async function getOpportunityById(opportunityId: string) {
	const docRef = doc(db, "opportunities", opportunityId).withConverter(opportunityConverter);
	const docSnap = await getDoc(docRef);
	if (!docSnap.exists()) {
		console.log("No such document!");
		return null;
	}

	return docSnap.data() as Opportunity;
}

export async function getInterestedUsersForOpportunity(opId: string): Promise<UserModel[]> {
	const opsRef = collection(db, "opportunities");
	const interestedCollection = collection(opsRef, `${opId}/interestedUsers`);
	const interestedUsers = await getDocs(interestedCollection);

	return (
		await Promise.all(
			interestedUsers.docs.map(async (doc) => {
				return await getUserById(doc.id);
			})
		)
	).filter((u) => u !== null) as UserModel[];
}

const featuredPerformersCache = new LRUCache<string, UserModel[]>({
	max: 1,
});
export async function getFeaturedPerformers(): Promise<UserModel[]> {
	const cached = featuredPerformersCache.get("featuredPerformers");
	if (cached !== undefined) {
		return cached;
	}

	const leadersRef = collection(db, "leaderboard");
	const leadersSnap = doc(leadersRef, "leaders");
	const leadersDoc = await getDoc(leadersSnap);
	const { featuredPerformers } = leadersDoc.data() as {
		featuredPerformers: string[];
	};
	const featured = (await Promise.all(featuredPerformers.map(getUserByUsername))).filter(
		(u) => u !== null
	) as UserModel[];

	featuredPerformersCache.set("featuredPerformers", featured);
	return featured;
}

export async function getReviewsByPerformerId(userId: string): Promise<Review[]> {
	const reviewsCollection = collection(db, `reviews/${userId}/performerReviews`);
	const querySnapshot = query(reviewsCollection, orderBy("timestamp", "desc")).withConverter(
		reviewConverter
	);

	const queryDocs = await getDocs(querySnapshot);

	return queryDocs.docs.map((doc) => doc.data());
}

export async function getBookingsByRequestee(
	userId: string,
	params?: { limit: number }
): Promise<Booking[]> {
	const bookingsCollection = collection(db, "bookings");
	const querySnapshot = query(
		bookingsCollection,
		where("requesteeId", "==", userId),
		where("status", "==", "confirmed"),
		orderBy("timestamp", "desc"),
		limit(params?.limit ?? 100)
	).withConverter(bookingConverter);
	const queryDocs = await getDocs(querySnapshot);

	return queryDocs.docs.map((doc) => doc.data());
}

export async function getBookingsByRequester(
	userId: string,
	params?: { limit: number }
): Promise<Booking[]> {
	const bookingsCollection = collection(db, "bookings");
	const querySnapshot = query(
		bookingsCollection,
		where("requesterId", "==", userId),
		where("status", "==", "confirmed"),
		orderBy("timestamp", "desc"),
		limit(params?.limit ?? 100)
	).withConverter(bookingConverter);
	const queryDocs = await getDocs(querySnapshot);

	return queryDocs.docs.map((doc) => doc.data());
}

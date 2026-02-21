import type { Metadata, ResolvingMetadata } from "next";
import { notFound } from "next/navigation";
import Footer from "@/components/Footer";
import ProfileViewServer, { type ProfileData } from "@/components/profile/ProfileViewServer";
import {
	getBookingsByRequestee,
	getBookingsByRequester,
	getLatestPerformerReviewByPerformerId,
	getUserById,
	getUserByUsername,
} from "@/data/database";
import { profileImage, type UserModel } from "@/domain/types/user_model";

type Props = {
	params: Promise<{ username: string }>;
	searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
};

const getUserByIdUrl = `${process.env.NEXT_PUBLIC_API_URL}/getUserByUsername`;

export async function generateMetadata(
	props: Props,
	_parent: ResolvingMetadata
): Promise<Metadata> {
	const params = await props.params;
	const metadataBase = "https://tapped.ai";
	try {
		const username = params.username;

		const res = await fetch(`${getUserByIdUrl}?username=${username}`);
		const user = (await res.json()) as UserModel;

		const imageSrc = profileImage(user);
		const displayName = user.artistName || user.username;
		return {
			metadataBase: new URL(metadataBase),
			title: `${displayName} | tapped ai`,
			description: `${displayName} on tapped ai | create a world tour from your iPhone`,
			openGraph: {
				type: "website",
				url: `${metadataBase}/u/${username}`,
				title: `${displayName}`,
				description: `${displayName} on tapped ai`,
				siteName: "tapped ai",
				images: [{ url: imageSrc }],
			},
			twitter: {
				card: "summary_large_image",
				site: "@tappedx",
				title: `${displayName}`,
				description: `${displayName} on tapped ai | create a world tour from your iPhone`,
				images: imageSrc,
			},
		};
	} catch (e) {
		console.log(e);
		return {
			metadataBase: new URL(metadataBase),
			title: "tapped ai",
			description: "tapped ai",
			openGraph: {
				type: "website",
				url: metadataBase,
				title: "tapped ai",
				description: "tapped ai | create a world your from your iPhone",
				siteName: "tapped ai",
				images: [{ url: `${metadataBase}/og.png` }],
			},
			twitter: {
				card: "summary_large_image",
				site: "@tappedx",
				title: "tapped ai",
				description: "tapped ai | create a world your from your iPhone",
				images: `${metadataBase}/og.png`,
			},
		};
	}
}

async function fetchProfileData(username: string): Promise<ProfileData | null> {
	const user = await getUserByUsername(username);
	if (!user) {
		return null;
	}

	const [requesteeBookings, requesterBookings, latestReview, topPerformers] = await Promise.all([
		getBookingsByRequestee(user.id, { limit: 5 }),
		getBookingsByRequester(user.id, { limit: 5 }),
		getLatestPerformerReviewByPerformerId(user.id),
		fetchTopPerformers(user.venueInfo?.topPerformerIds ?? []),
	]);

	const bookings = [...requesteeBookings, ...requesterBookings].sort(
		(a, b) => b.startTime.getTime() - a.startTime.getTime()
	);

	const reviewer = latestReview
		? await fetchReviewer(latestReview.type, latestReview.performerId, latestReview.bookerId)
		: null;

	return {
		user,
		bookings,
		latestReview: latestReview ?? null,
		topPerformers,
		reviewer,
	};
}

async function fetchTopPerformers(topPerformerIds: string[]): Promise<UserModel[]> {
	if (topPerformerIds.length === 0) {
		return [];
	}
	const performers = await Promise.all(topPerformerIds.map((id) => getUserById(id)));
	return performers.filter((user): user is UserModel => user !== null);
}

async function fetchReviewer(
	type: "performer" | "booker",
	performerId: string,
	bookerId: string
): Promise<UserModel | null> {
	const reviewerId = type === "booker" ? performerId : bookerId;
	return (await getUserById(reviewerId)) ?? null;
}

export default async function Page(props: Props) {
	const params = await props.params;
	const username = params.username;

	const data = await fetchProfileData(username);
	if (!data) {
		notFound();
	}

	return (
		<div>
			<ProfileViewServer data={data} />
			<Footer />
		</div>
	);
}

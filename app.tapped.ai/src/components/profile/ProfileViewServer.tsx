import Link from "next/link";
import type { Booking } from "@/domain/types/booking";
import type { Review } from "@/domain/types/review";
import type { UserModel } from "@/domain/types/user_model";
import BookingHistoryPreview from "./BookingHistoryPreview";
import DownloadTheAppSection from "./DownloadTheAppSection";
import ProfileHeaderServer from "./ProfileHeaderServer";
import ReviewTileServer from "./ReviewTileServer";
import TopPerformersClient from "./TopPerformersClient";

export type ProfileData = {
	user: UserModel;
	bookings: Booking[];
	latestReview: Review | null;
	topPerformers: UserModel[];
	reviewer: UserModel | null;
};

export default function ProfileViewServer({ data }: { data: ProfileData }) {
	const { user, bookings, topPerformers, latestReview, reviewer } = data;

	return (
		<div className="md:relative md:flex md:justify-center">
			<div className="md:w-[30vw] md:px-6">
				<div className="md:sticky md:top-0">
					<ProfileHeaderServer user={user} />
				</div>
			</div>
			<div className="lg:grow">
				<BuildRows
					user={user}
					bookings={bookings}
					topPerformers={topPerformers}
					latestReview={latestReview}
					reviewer={reviewer}
				/>
			</div>
		</div>
	);
}

function BuildRows({
	user,
	bookings,
	topPerformers,
	latestReview,
	reviewer,
}: {
	user: UserModel;
	bookings: Booking[];
	topPerformers: UserModel[];
	latestReview: Review | null;
	reviewer: UserModel | null;
}) {
	return (
		<div className="px-3 py-6 md:w-[70vw] md:px-24 md:py-12">
			{topPerformers.length > 0 && (
				<>
					<div className="h-4" />
					<div>
						<h2 className="font-bold text-2xl">top performers</h2>
						<div className="h-2" />
						<TopPerformersClient users={topPerformers} />
					</div>
				</>
			)}
			{bookings.length !== 0 && (
				<>
					<div className="h-4" />
					<div>
						<div className="flex flex-row items-center">
							<h2 className="font-bold text-2xl">booking history</h2>
							<div className="w-2" />
							<Link href={`/history/${user.id}`} className="text-blue-500 text-sm">
								see all
							</Link>
						</div>
						<div className="h-2" />
						<BookingHistoryPreview user={user} bookings={bookings} />
					</div>
				</>
			)}
			{latestReview && (
				<>
					<div className="h-8" />
					<div>
						<div className="flex flex-row items-center">
							<h2 className="font-bold text-2xl">reviews</h2>
							<div className="w-2" />
							<Link href={`/reviews/${user.id}`} className="text-blue-500 text-sm">
								see all
							</Link>
						</div>
						<div className="h-2" />
						<ReviewTileServer review={latestReview} reviewer={reviewer} />
					</div>
				</>
			)}
			{user.bio !== "" && (
				<>
					<div className="h-8" />
					<div>
						<h2 className="font-bold text-2xl">about</h2>
						<div className="h-2" />
						<p>{user.bio}</p>
					</div>
				</>
			)}
			<div className="h-8" />
			<DownloadTheAppSection />
		</div>
	);
}

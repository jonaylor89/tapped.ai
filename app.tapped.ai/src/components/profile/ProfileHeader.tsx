import { BadgeCheck, Facebook, Link2, MapPinned, MicVocal, Network } from "lucide-react";
import { Manrope } from "next/font/google";
import Image from "next/image";
import Link from "next/link";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import GaugeComponent from "react-gauge-component";
import InstagramButton from "@/components/profile/InstagramButton";
import SpotifyButton from "@/components/profile/SpotifyButton";
import TiktokButton from "@/components/profile/TiktokButton";
import TwitterButton from "@/components/profile/TwitterButton";
import UserInfoSection from "@/components/UserInfoSection";
import { Button } from "@/components/ui/button";
import {
	getBookingCount,
	getBookingsByRequestee,
	getBookingsByRequester,
	getLatestPerformerReviewByPerformerId,
	getUserById,
	isVerified,
} from "@/data/database";
import type { Booking } from "@/domain/types/booking";
import type { Review } from "@/domain/types/review";
import {
	performerScore,
	profileImage,
	reviewCount,
	type UserModel,
	userAudienceSize,
} from "@/domain/types/user_model";
import { cn } from "@/lib/utils";
import { trackEvent } from "@/utils/tracking";
import AppStoreButton from "../appstorebuttons/AppStoreButton";
import GooglePlayButton from "../appstorebuttons/GooglePlayButton";
import { LoadingSpinner } from "../LoadingSpinner";
import UserCluster from "../UserCluster";
import { Card } from "../ui/card";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../ui/tooltip";
import { useToast } from "../ui/use-toast";
import BookingHistoryPreview from "./BookingHistoryPreview";
import DayOfWeekGraph from "./DayOrWeekGraph";
import EmbededMap from "./EmbededMap";
import ReviewTile from "./ReviewTile";

const manrope = Manrope({
	subsets: ["latin"],
	weight: ["700", "800"],
});

export default function ProfileHeader({ user, full = false }: { user: UserModel; full?: boolean }) {
	const imageSrc = profileImage(user);
	const audience = userAudienceSize(user);
	const firstValue = user.venueInfo?.capacity ?? audience;
	const firstLabel = user.venueInfo?.capacity ? "capacity" : "audience";
	const category = user.performerInfo?.category;
	const isPerformer = user.performerInfo !== null && user.performerInfo !== undefined;
	const isVenue = user.venueInfo !== null && user.venueInfo !== undefined;
	const dayOfWeekData = user.venueInfo?.bookingsByDayOfWeek ?? [];
	const websiteUrl = user.venueInfo?.websiteUrl?.startsWith("http")
		? user.venueInfo?.websiteUrl
		: `https://${user.venueInfo?.websiteUrl}`;

	const { resolvedTheme } = useTheme();

	const [bookings, setBookings] = useState<Booking[]>([]);
	const [latestReview, setLatestReview] = useState<Review | null>(null);

	const { toast } = useToast();
	const [verified, setVerified] = useState(false);
	useEffect(() => {
		const getIfVerified = async () => {
			const res = await isVerified(user.id);
			setVerified(res);
		};

		getIfVerified();
	}, [user.id]);

	const [bookingCount, setBookingCount] = useState<number | null>(null);
	useEffect(() => {
		const fetchBookingCount = async () => {
			const bookingCount = await getBookingCount(user.id);
			setBookingCount(bookingCount);
		};
		fetchBookingCount();
	}, [user.id]);

	useEffect(() => {
		const fetchBooking = async () => {
			if (user === null || !full) {
				return;
			}

			// fetch latest booking
			const latestRequesteeBookings = await getBookingsByRequestee(user.id, { limit: 40 });
			const latestRequesterBookings = await getBookingsByRequester(user.id, { limit: 40 });
			const latestBookings = latestRequesteeBookings
				.concat(latestRequesterBookings)
				.sort((a, b) => {
					return b.startTime.getTime() - a.startTime.getTime();
				});

			setBookings(latestBookings);
		};
		fetchBooking();

		const fetchLatestReview = async () => {
			if (user === null) {
				return;
			}

			// get latest review
			const latestPerformerReview = await getLatestPerformerReviewByPerformerId(user.id);
			const latestBookerReview = await getLatestPerformerReviewByPerformerId(user.id);

			const latestReview = latestPerformerReview ?? latestBookerReview ?? null;
			setLatestReview(latestReview);
		};
		fetchLatestReview();
	}, [user, full]);

	return (
		<div className="w-full px-0 py-6 md:py-12">
			<div className="flex flex-row flex-col items-center justify-start">
				<div className="flex aspect-square w-full flex-col items-center justify-center">
					<div className="relative z-1 h-full w-full overflow-hidden rounded-xl">
						<Image
							src={imageSrc}
							alt={`${user.artistName} profile picture`}
							fill
							style={{
								objectFit: "cover",
								objectPosition: "center",
							}}
						/>
					</div>
				</div>
				<div className="w-4 md:h-6" />
				<div className="">
					<h1
						className={cn(
							"line-clamp-3 flex-1 overflow-ellipsis font-extrabold text-4xl md:text-5xl",
							manrope.className
						)}
					>
						{user.artistName ?? user.username}
						{verified && (
							<span className="inline">
								<TooltipProvider disableHoverableContent>
									<Tooltip>
										<TooltipTrigger>
											<BadgeCheck />
										</TooltipTrigger>
										<TooltipContent side="right" align="start" alignOffset={2}>
											verified
										</TooltipContent>
									</Tooltip>
								</TooltipProvider>
							</span>
						)}
					</h1>
				</div>
			</div>
			<div className="h-4" />
			<div className="flex flex-row items-center justify-around">
				<div className="flex flex-col items-center justify-center">
					<h3 className="font-bold text-2xl">{firstValue.toLocaleString()}</h3>
					<p className="text-font text-gray-500 text-xs">{firstLabel}</p>
				</div>
				{isPerformer ? (
					<div className="flex flex-col items-center justify-center">
						<h3 className="font-bold text-2xl">
							{bookingCount !== null ? (
								bookingCount.toLocaleString()
							) : (
								<span>
									<LoadingSpinner />
								</span>
							)}
						</h3>
						<p className="text-font text-gray-500 text-xs">bookings</p>
					</div>
				) : (
					<div className="flex flex-col items-center justify-center">
						<h3 className="font-bold text-2xl">{reviewCount(user)}</h3>
						<p className="text-font text-gray-500 text-xs">reviews</p>
					</div>
				)}
				<div className="flex flex-col items-center justify-center">
					<h3 className="font-bold text-2xl">
						{user.performerInfo?.rating ? `${user.performerInfo?.rating}/5` : "N/A"}
					</h3>
					<p className="text-gray-400 text-sm">rating</p>
				</div>
			</div>
			<div className="h-4" />
			<UserInfoSection user={user} />
			<div>
				<Link
					href="mailto:support@tapped.ai"
					className="cursor-pointer text-blue-500 text-sm transition-all duration-150 ease-in-out hover:scale-105"
				>
					something incorrect? contact us
				</Link>
			</div>
			{category && (
				<>
					<div className="h-4" />
					<Card
						className="flex w-full cursor-pointer items-center justify-center transition-all duration-150 ease-in-out hover:scale-103"
						onClick={() => {
							trackEvent("gauge_clicked", {
								performer_id: user.id,
							});
							toast({
								title: `${category} performer`,
								description:
									"performers are ranked based on how big their shows are, how frequent they are, and how they're selling tickets",
							});
						}}
					>
						<GaugeComponent
							value={performerScore(category)}
							type="radial"
							labels={{
								valueLabel: {
									style: {
										color: resolvedTheme === "dark" ? "#FFF" : "#000",
									},
									formatTextValue: () => {
										return `${category}`;
									},
								},
							}}
							arc={{
								colorArray: ["#9E9E9E", "#40C4FF", "#FF9800", "#9C27B0", "#F44336"],
								subArcs: [
									{ limit: 33 },
									{ limit: 66 },
									{ limit: 80 },
									{ limit: 95 },
									{ limit: 100 },
								],
								padding: 0.02,
								width: 0.3,
							}}
							pointer={{
								elastic: true,
								animationDelay: 0,
							}}
						/>
					</Card>
				</>
			)}
			<div className="h-4" />
			<div className="flex flex-row items-center justify-around">
				{user.socialFollowing?.instagramHandle && (
					<InstagramButton instagramHandle={user.socialFollowing.instagramHandle} />
				)}
				{user.socialFollowing?.twitterHandle && (
					<TwitterButton twitterHandle={user.socialFollowing.twitterHandle} />
				)}
				{user.socialFollowing?.facebookHandle && (
					<Link
						href={`https://facebook.com/${user.socialFollowing.facebookHandle}`}
						target="_blank"
						rel="noopener noreferrer"
					>
						<Button variant={"outline"} size={"icon"}>
							<Facebook />
						</Button>
					</Link>
				)}
				{user.socialFollowing?.tiktokHandle && (
					<TiktokButton tiktokHandle={user.socialFollowing.tiktokHandle} />
				)}
				{user.performerInfo?.spotifyId && (
					<SpotifyButton spotifyId={user.performerInfo.spotifyId} />
				)}
				{user.venueInfo?.websiteUrl && (
					<Link href={websiteUrl} target="_blank" rel="noopener noreferrer">
						<Button variant={"outline"} size={"icon"}>
							<Link2 />
						</Button>
					</Link>
				)}
			</div>
			<div className="h-4" />
			{isVenue && <DayOfWeekGraph dayOfWeekData={dayOfWeekData} />}
			<div className="h-4" />
			{full && <FullRows user={user} bookings={bookings} latestReview={latestReview} />}
		</div>
	);
}

function FullRows({
	user,
	bookings,
	latestReview,
}: {
	user: UserModel;
	bookings: Booking[];
	latestReview: Review | null;
}) {
	const appleUrl = "https://apps.apple.com/us/app/tapped-network/id1574937614";
	const googleUrl = "https://play.google.com/store/apps/details?id=com.intheloopstudio";

	const isVenue = user.venueInfo !== null && user.venueInfo !== undefined;
	const lat = user.location?.lat ?? null;
	const lng = user.location?.lng ?? null;

	const [topPerformers, setTopPerformers] = useState<UserModel[]>([]);
	useEffect(() => {
		const topPerformerIds = user.venueInfo?.topPerformerIds ?? [];
		const fetchTopPerformers = async () => {
			const performers = (
				await Promise.all(
					topPerformerIds.map(async (id) => {
						return await getUserById(id);
					})
				)
			).filter((user) => user !== null) as UserModel[];
			setTopPerformers(performers);
		};
		fetchTopPerformers();
	}, [user.venueInfo]);

	return (
		<div className="px-3">
			{topPerformers.length > 0 && (
				<>
					<div className="h-4" />
					<div>
						<h2 className="font-bold text-2xl">top performers</h2>
						<div className="h-2" />
						<UserCluster
							users={topPerformers}
							onClick={(performer) => {
								trackEvent("top_performer_click", {
									performer_id: performer.id,
								});
							}}
						/>
					</div>
				</>
			)}
			{bookings.length !== 0 && (
				<>
					<div className="h-8" />
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
						<ReviewTile review={latestReview} />
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
			<div className="h-4" />
			{isVenue && lat !== null && lng !== null && (
				<>
					<h2 className="font-bold text-2xl">location</h2>
					<EmbededMap lat={lat} lng={lng} />
				</>
			)}
			<div className="h-8" />
			<div className="flex flex-row">
				<div className="flex flex-col gap-4">
					<h2 className="font-bold text-2xl">download the tapped app</h2>
					<div className="flex flex-row gap-3">
						<Button variant="outline" size="icon" disabled>
							<MapPinned />
						</Button>
						<p className="flex-1">
							discover the venues in your city, with tailored recommendations synced to your booking
							history
						</p>
					</div>
					<div className="flex flex-row gap-3">
						<Button variant="outline" size="icon" disabled>
							<MicVocal />
						</Button>
						<p className="flex-1">
							keep track of what&apos;s coming up by getting notified about new events and gig
							opportunities
						</p>
					</div>
					<div className="flex flex-row gap-3">
						<Button variant="outline" size="icon" disabled>
							<Network />
						</Button>
						<p className="flex-1">
							we’ve made it easy to request to perform at thousands of venues across the country. no
							stress.
						</p>
					</div>
					<div className="flex flex-col items-center justify-start gap-4">
						<GooglePlayButton url={googleUrl} theme={"dark"} />
						<AppStoreButton url={appleUrl} theme={"dark"} />
					</div>
				</div>
				<div className="hidden flex-0">
					<Image src="/images/icon_1024.png" alt="Tapped App Icon" width={124} height={124} />
				</div>
			</div>
		</div>
	);
}

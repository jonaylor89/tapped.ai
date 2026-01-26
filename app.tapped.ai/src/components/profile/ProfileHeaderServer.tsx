import { BadgeCheck, Facebook, Link2 } from "lucide-react";
import { Manrope } from "next/font/google";
import Image from "next/image";
import Link from "next/link";
import InstagramButton from "@/components/profile/InstagramButton";
import SpotifyButton from "@/components/profile/SpotifyButton";
import TiktokButton from "@/components/profile/TiktokButton";
import TwitterButton from "@/components/profile/TwitterButton";
import UserInfoSection from "@/components/user/UserInfoSection";
import { Button } from "@/components/ui/button";
import {
	profileImage,
	reviewCount,
	type UserModel,
	userAudienceSize,
} from "@/domain/types/user_model";
import { cn } from "@/lib/utils";
import DayOfWeekGraph from "./DayOrWeekGraph";
import ProfileHeaderClient from "./ProfileHeaderClient";

const manrope = Manrope({
	subsets: ["latin"],
	weight: ["700", "800"],
});

type ProfileHeaderServerProps = {
	user: UserModel;
	verified?: boolean;
	bookingCount?: number | null;
};

export default function ProfileHeaderServer({
	user,
	verified = false,
	bookingCount = null,
}: ProfileHeaderServerProps) {
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
								<BadgeCheck className="inline ml-1" />
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
							{bookingCount !== null ? bookingCount.toLocaleString() : "—"}
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
					<ProfileHeaderClient user={user} category={category} />
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
		</div>
	);
}

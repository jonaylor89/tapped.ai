import type { Option } from "./option";

export type Location = {
	lat: number;
	lng: number;
	placeId: string;
};

export type SocialFollowing = {
	youtubeChannelId?: Option<string>;
	tiktokHandle?: Option<string>;
	tiktokFollowers: number;
	instagramHandle?: Option<string>;
	instagramFollowers: number;
	twitterHandle?: Option<string>;
	twitterFollowers: number;
	facebookHandle?: Option<string>;
	facebookFollowers: number;
	spotifyUrl?: Option<string>;
	soundcloudHandle?: Option<string>;
	soundcloudFollowers: number;
	audiusHandle?: Option<string>;
	audiusFollowers: number;
	twitchHandle?: Option<string>;
	twitchFollowers: number;
};

export type BookerInfo = {
	rating?: Option<number>;
	reviewCount: number;
};

export type PerformerCategory =
	| "undiscovered"
	| "emerging"
	| "hometownHero"
	| "mainstream"
	| "legendary";
export type PerformerInfo = {
	pressKitUrl?: Option<string>;
	genres: string[];
	rating?: Option<number>;
	reviewCount: number;
	label: string;
	spotifyId?: Option<string>;
	category: PerformerCategory;
};

export function suggestTicketPriceRange(category: PerformerCategory): [number, number] {
	const mapping: Record<PerformerCategory, [number, number]> = {
		undiscovered: [0, 10],
		emerging: [10, 20],
		hometownHero: [20, 40],
		mainstream: [40, 75],
		legendary: [75, 100],
	};

	return mapping[category];
}

export type VenueInfo = {
	genres?: string[];
	websiteUrl?: Option<string>;
	bookingEmail?: Option<string>;
	phoneNumber?: Option<string>;
	autoReply?: Option<string>;
	capacity?: Option<number>;
	idealPerformerProfile?: Option<string>;
	type?: Option<string>;
	productionInfo?: Option<string>;
	frontOfHouse?: Option<string>;
	monitors?: Option<string>;
	microphones?: Option<string>;
	lights?: Option<string>;
	topPerformerIds?: string[];
	bookingsByDayOfWeek?: number[];
};

export type EmailNotifications = {
	appReleases: boolean;
	tappedUpdates: boolean;
	bookingRequests: boolean;
};

export type PushNotifications = {
	appReleases: boolean;
	tappedUpdates: boolean;
	bookingRequests: boolean;
	directMessages: boolean;
};

export type UserModel = {
	id: string;
	email?: string;
	unclaimed: boolean;
	timestamp?: Date;
	username: string;
	artistName: string;
	bio: string;
	occupations: string[];
	profilePicture: Option<string>;
	location: Option<Location>;
	performerInfo: Option<PerformerInfo>;
	venueInfo: Option<VenueInfo>;
	bookerInfo: Option<BookerInfo>;
	emailNotifications: EmailNotifications;
	pushNotifications: PushNotifications;
	deleted: boolean;
	socialFollowing: SocialFollowing;
	stripeConnectedAccountId: Option<string>;
	stripeCustomerId: Option<string>;
};

export const performerScore = (category: PerformerCategory): number => {
	const range = performerScoreRange(category);
	return Math.round((range[0] + range[0]) / 2);
};

const performerScoreRange = (category: PerformerCategory): [number, number] => {
	const mapping: {
		[key in PerformerCategory]: [number, number];
	} = {
		undiscovered: [0, 33],
		emerging: [33, 66],
		hometownHero: [66, 80],
		mainstream: [80, 95],
		legendary: [95, 100],
	};

	return mapping[category];
};

export const reviewCount = (user: UserModel): number =>
	(user.bookerInfo?.reviewCount ?? 0) + (user.performerInfo?.reviewCount ?? 0);

export const userAudienceSize = (user: UserModel): number =>
	totalSocialFollowing(user.socialFollowing);

export const totalSocialFollowing = (socialFollowing: SocialFollowing | null): number =>
	(socialFollowing?.twitterFollowers ?? 0) +
	(socialFollowing?.instagramFollowers ?? 0) +
	(socialFollowing?.tiktokFollowers ?? 0);

const isVenue = (user: UserModel): boolean =>
	user.venueInfo !== null && user.venueInfo !== undefined;

export const profileImage = (user: UserModel): string =>
	isVenue(user)
		? imageOrDefault({
				url: user.profilePicture,
				defaultImage: "/images/default_venue.jpg",
			})
		: imageOrDefault({
				url: user.profilePicture,
				defaultImage: "/images/default_avatar.jpg",
			});

export const imageOrDefault = ({
	url,
	defaultImage = "/images/default_avatar.jpg",
}: {
	url: string | null | undefined;
	defaultImage?: string;
}): string => {
	if (url === undefined || url === null) {
		return defaultImage;
	}

	return url;
};

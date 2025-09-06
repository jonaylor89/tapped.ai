
import { Timestamp } from "firebase-admin/firestore";

export type Option<T> = T | null;

export type CrawferInfo = {
    timestamp: Date;
    runId: string;
    encodedLink: string;
};

export type EventData = {
    crawlerInfo: CrawferInfo;
    eventId: string;
    venue: UserModel;
    isMusicEvent: boolean;
    url: Option<string>;
    title: Option<string>;
    description: Option<string>;
    performers: string[];
    ticketPrice: Option<number>;
    doorPrice: Option<number>;
    startTime: Date;
    endTime: Date;
    flierUrl: Option<string>;
}

export type Booking = {
    id: string;
    scraperInfo?: {
        scraperId: string;
        runId: string;
    } | null;
    crawlerInfo: CrawferInfo;
    serviceId: Option<string>;
    name: string;
    note: string;
    requesterId: string;
    requesteeId: string;
    status: string;
    rate: number;
    startTime: Timestamp;
    endTime: Timestamp;
    timestamp: Timestamp;
    flierUrl: Option<string>;
    eventUrl: Option<string>;
    location: Option<Location>;
    genres: string[];
    referenceEventId: Option<string>;
}

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

export type PerformerInfo = {
    pressKitUrl?: Option<string>;
    genres: string[];
    rating?: Option<number>;
    reviewCount: number;
    label: string;
    spotifyId?: Option<string>;
};

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
    email: string;
    unclaimed: boolean;
    timestamp: Timestamp;
    username: string;
    artistName: string;
    bio: string;
    occupations: string[];
    profilePicture: Option<string>;
    location: Option<Location>;
    badgesCount: number;
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

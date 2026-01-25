/* eslint-disable sonarjs/no-nested-template-literals */

import { Timestamp } from "firebase/firestore";
import Typesense from "typesense";
import type { PerformerInfo, UserModel } from "@/domain/types/user_model";

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

// Initialize Typesense client
export const typesenseClient = new Typesense.Client({
	nodes: [
		{
			host: process.env.TYPESENSE_HOST || "localhost",
			port: parseInt(process.env.TYPESENSE_PORT || "8108", 10),
			protocol: process.env.TYPESENSE_PROTOCOL || "http",
		},
	],
	apiKey: process.env.TYPESENSE_SEARCH_API_KEY || "",
	connectionTimeoutSeconds: 10,
});

export type BoundingBox = {
	readonly sw: { lat: number; lng: number };
	readonly ne: { lat: number; lng: number };
};

export async function queryVenuesInBoundedBox(
	bounds: BoundingBox | null,
	{ hitsPerPage, venueGenres, unclaimed, minCapacity, maxCapacity }: UserSearchOptions
): Promise<UserModel[]> {
	const filterBy: string[] = [];

	// Venue filter
	filterBy.push("occupations:=[Venue, venue]");

	// Deleted filter
	filterBy.push("deleted:=false");

	// Venue genres filter
	if (venueGenres != null && venueGenres.length > 0) {
		filterBy.push(`venueInfo.genres:=[${venueGenres.map((g) => `'${g}'`).join(", ")}]`);
	}

	// Unclaimed filter
	if (unclaimed != null) {
		filterBy.push(`unclaimed:=${unclaimed}`);
	}

	// Capacity filters
	if (minCapacity != null) {
		filterBy.push(`venueInfo.capacity:>=${minCapacity}`);
	}

	if (maxCapacity != null) {
		filterBy.push(`venueInfo.capacity:<=${maxCapacity}`);
	}

	try {
		const searchParameters = {
			q: "*",
			query_by: "artistName,username,bio",
			filter_by: filterBy.join(" && "),
			per_page: hitsPerPage,
		};

		// Add geo polygon filter for bounding box if bounds are provided
		if (bounds !== null) {
			const { sw, ne } = bounds;
			// Create polygon from bounding box coordinates (counter-clockwise order)
			// sw = southwest corner, ne = northeast corner
			// Rectangle: sw -> se -> ne -> nw -> sw
			const polygonFilter = `location:(${sw.lat}, ${sw.lng}, ${sw.lat}, ${ne.lng}, ${ne.lat}, ${ne.lng}, ${ne.lat}, ${sw.lng})`;
			filterBy.push(polygonFilter);
			searchParameters.filter_by = filterBy.join(" && ");
		}

		const response = await typesenseClient
			.collections("users")
			.documents()
			.search(searchParameters);

		return response.hits?.map((hit) => convertTypesenseDocumentToUserModel(hit.document as TypesenseDocument)) || [];
	} catch (e) {
		console.error(e);
		return [];
	}
}

export async function queryUsers(
	query: string,
	{
		hitsPerPage,
		labels,
		genres,
		occupations,
		occupationsBlacklist,
		venueGenres,
		unclaimed,
		lat,
		lng,
		radius = 50_000,
		minCapacity,
		maxCapacity,
	}: UserSearchOptions
): Promise<UserModel[]> {
	const filterBy: string[] = [];

	// Deleted filter
	filterBy.push("deleted:=false");

	// Labels filter
	if (labels != null && labels.length > 0) {
		filterBy.push(`performerInfo.label:=[${labels.map((l) => `'${l}'`).join(", ")}]`);
	}

	// Genres filter
	if (genres != null && genres.length > 0) {
		filterBy.push(`performerInfo.genres:=[${genres.map((g) => `'${g}'`).join(", ")}]`);
	}

	// Occupations filter
	if (occupations != null && occupations.length > 0) {
		filterBy.push(`occupations:=[${occupations.map((o) => `'${o}'`).join(", ")}]`);
	}

	// Occupations blacklist filter
	if (occupationsBlacklist != null && occupationsBlacklist.length > 0) {
		filterBy.push(`occupations:!=[${occupationsBlacklist.map((o) => `'${o}'`).join(", ")}]`);
	}

	// Venue genres filter
	if (venueGenres != null && venueGenres.length > 0) {
		filterBy.push(`venueInfo.genres:=[${venueGenres.map((g) => `'${g}'`).join(", ")}]`);
	}

	// Unclaimed filter
	if (unclaimed != null) {
		filterBy.push(`unclaimed:=${unclaimed}`);
	}

	// Capacity filters
	if (minCapacity != null) {
		filterBy.push(`venueInfo.capacity:>=${minCapacity}`);
	}

	if (maxCapacity != null) {
		filterBy.push(`venueInfo.capacity:<=${maxCapacity}`);
	}

	try {
		const searchParameters: {
			q: string;
			query_by: string;
			filter_by: string;
			per_page: number;
			sort_by?: string;
		} = {
			q: query || "*",
			query_by: "artistName,username,bio,performerInfo.label,venueInfo.type",
			filter_by: filterBy.join(" && "),
			per_page: hitsPerPage ?? 10,
		};

		// Add geo location filter and sorting if coordinates are provided
		if (lat != null && lng != null) {
			// Convert radius from meters to kilometers for Typesense
			const radiusKm = radius / 1000;
			// Add radius filter using correct Typesense syntax: location:(lat, lng, radius km)
			filterBy.push(`location:(${lat}, ${lng}, ${radiusKm} km)`);
			searchParameters.filter_by = filterBy.join(" && ");
			// Sort by distance from the specified location
			searchParameters.sort_by = `location(${lat}, ${lng}):asc`;
		} else {
			// Default sorting when no location is specified
			searchParameters.sort_by = "_text_match:desc";
		}

		const response = await typesenseClient
			.collections("users")
			.documents()
			.search(searchParameters);

		return response.hits?.map((hit) => convertTypesenseDocumentToUserModel(hit.document as TypesenseDocument)) || [];
	} catch (e) {
		console.error(e);
		return [];
	}
}

type TypesenseDocument = { location?: unknown } & Record<string, unknown>;

const getString = (value: unknown, fallback = "") => (typeof value === "string" ? value : fallback);
const getBoolean = (value: unknown, fallback = false) =>
	typeof value === "boolean" ? value : fallback;
const getNumber = (value: unknown, fallback = 0) => (typeof value === "number" ? value : fallback);
const getStringArray = (value: unknown) =>
	Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
const getNumberArray = (value: unknown) =>
	Array.isArray(value) ? value.filter((item): item is number => typeof item === "number") : [];

// Helper function to convert Typesense document to UserModel
export function convertTypesenseDocumentToUserModel(doc: TypesenseDocument): UserModel {
	const location = Array.isArray(doc.location) ? doc.location : null;
	const hasLocation =
		location &&
		location.length >= 2 &&
		typeof location[0] === "number" &&
		typeof location[1] === "number";

	const performerInfoKeys = [
		"performerInfo.label",
		"performerInfo.genres",
		"performerInfo.rating",
		"performerInfo.reviewCount",
		"performerInfo.spotifyId",
		"performerInfo.category",
		"performerInfo.pressKitUrl",
	];

	const venueInfoKeys = [
		"venueInfo.genres",
		"venueInfo.websiteUrl",
		"venueInfo.bookingEmail",
		"venueInfo.phoneNumber",
		"venueInfo.autoReply",
		"venueInfo.capacity",
		"venueInfo.idealPerformerProfile",
		"venueInfo.type",
		"venueInfo.productionInfo",
		"venueInfo.frontOfHouse",
		"venueInfo.monitors",
		"venueInfo.microphones",
		"venueInfo.lights",
		"venueInfo.topPerformerIds",
		"venueInfo.bookingsByDayOfWeek",
	];

	const bookerInfoKeys = ["bookerInfo.rating", "bookerInfo.reviewCount"];
	const emailNotificationKeys = [
		"emailNotifications.appReleases",
		"emailNotifications.tappedUpdates",
		"emailNotifications.bookingRequests",
	];
	const pushNotificationKeys = [
		"pushNotifications.appReleases",
		"pushNotifications.tappedUpdates",
		"pushNotifications.bookingRequests",
		"pushNotifications.directMessages",
	];

	const hasPerformerInfo = performerInfoKeys.some((key) => doc[key] !== undefined);
	const hasVenueInfo = venueInfoKeys.some((key) => doc[key] !== undefined);
	const hasBookerInfo = bookerInfoKeys.some((key) => doc[key] !== undefined);
	const hasEmailNotifications = emailNotificationKeys.some((key) => doc[key] !== undefined);
	const hasPushNotifications = pushNotificationKeys.some((key) => doc[key] !== undefined);

	return {
		id: getString(doc.id),
		email: getString(doc.email),
		unclaimed: getBoolean(doc.unclaimed),
		timestamp: doc.timestamp
			? Timestamp.fromDate(new Date(getString(doc.timestamp)))
			: Timestamp.now(),
		username: getString(doc.username),
		artistName: getString(doc.artistName),
		bio: getString(doc.bio),
		occupations: getStringArray(doc.occupations),
		profilePicture: getString(doc.profilePicture, "") || null,
		location: hasLocation
			? {
					lat: location[0],
					lng: location[1],
					placeId: getString(doc["location.placeId"]),
				}
			: null,
		performerInfo: hasPerformerInfo
			? {
					pressKitUrl: getString(doc["performerInfo.pressKitUrl"], "") || null,
					genres: getStringArray(doc["performerInfo.genres"]),
					rating: getNumber(doc["performerInfo.rating"], 0) || null,
					reviewCount: getNumber(doc["performerInfo.reviewCount"]),
					label: getString(doc["performerInfo.label"]),
					spotifyId: getString(doc["performerInfo.spotifyId"], "") || null,
					category: getString(
						doc["performerInfo.category"],
						"undiscovered"
					) as PerformerInfo["category"],
				}
			: null,
		venueInfo: hasVenueInfo
			? {
					genres: getStringArray(doc["venueInfo.genres"]),
					websiteUrl: getString(doc["venueInfo.websiteUrl"], "") || null,
					bookingEmail: getString(doc["venueInfo.bookingEmail"], "") || null,
					phoneNumber: getString(doc["venueInfo.phoneNumber"], "") || null,
					autoReply: getString(doc["venueInfo.autoReply"], "") || null,
					capacity: getNumber(doc["venueInfo.capacity"]),
					idealPerformerProfile: getString(doc["venueInfo.idealPerformerProfile"], "") || null,
					type: getString(doc["venueInfo.type"], ""),
					productionInfo: getString(doc["venueInfo.productionInfo"], "") || null,
					frontOfHouse: getString(doc["venueInfo.frontOfHouse"], "") || null,
					monitors: getString(doc["venueInfo.monitors"], "") || null,
					microphones: getString(doc["venueInfo.microphones"], "") || null,
					lights: getString(doc["venueInfo.lights"], "") || null,
					topPerformerIds: getStringArray(doc["venueInfo.topPerformerIds"]),
					bookingsByDayOfWeek: getNumberArray(doc["venueInfo.bookingsByDayOfWeek"]),
				}
			: null,
		bookerInfo: hasBookerInfo
			? {
					rating: getNumber(doc["bookerInfo.rating"], 0) || null,
					reviewCount: getNumber(doc["bookerInfo.reviewCount"]),
				}
			: null,
		emailNotifications: {
			appReleases: hasEmailNotifications
				? getBoolean(doc["emailNotifications.appReleases"], true)
				: true,
			tappedUpdates: hasEmailNotifications
				? getBoolean(doc["emailNotifications.tappedUpdates"], true)
				: true,
			bookingRequests: hasEmailNotifications
				? getBoolean(doc["emailNotifications.bookingRequests"], true)
				: true,
		},
		pushNotifications: {
			appReleases: hasPushNotifications
				? getBoolean(doc["pushNotifications.appReleases"], true)
				: true,
			tappedUpdates: hasPushNotifications
				? getBoolean(doc["pushNotifications.tappedUpdates"], true)
				: true,
			bookingRequests: hasPushNotifications
				? getBoolean(doc["pushNotifications.bookingRequests"], true)
				: true,
			directMessages: hasPushNotifications
				? getBoolean(doc["pushNotifications.directMessages"], true)
				: true,
		},
		deleted: getBoolean(doc.deleted),
		socialFollowing: {
			youtubeChannelId: getString(doc["socialFollowing.youtubeChannelId"], "") || null,
			tiktokHandle: getString(doc["socialFollowing.tiktokHandle"], "") || null,
			tiktokFollowers: getNumber(doc["socialFollowing.tiktokFollowers"]),
			instagramHandle: getString(doc["socialFollowing.instagramHandle"], "") || null,
			instagramFollowers: getNumber(doc["socialFollowing.instagramFollowers"]),
			twitterHandle: getString(doc["socialFollowing.twitterHandle"], "") || null,
			twitterFollowers: getNumber(doc["socialFollowing.twitterFollowers"]),
			facebookHandle: getString(doc["socialFollowing.facebookHandle"], "") || null,
			facebookFollowers: getNumber(doc["socialFollowing.facebookFollowers"]),
			spotifyUrl: getString(doc["socialFollowing.spotifyUrl"], "") || null,
			soundcloudHandle: getString(doc["socialFollowing.soundcloudHandle"], "") || null,
			soundcloudFollowers: getNumber(doc["socialFollowing.soundcloudFollowers"]),
			audiusHandle: getString(doc["socialFollowing.audiusHandle"], "") || null,
			audiusFollowers: getNumber(doc["socialFollowing.audiusFollowers"]),
			twitchHandle: getString(doc["socialFollowing.twitchHandle"], "") || null,
			twitchFollowers: getNumber(doc["socialFollowing.twitchFollowers"]),
		},
		stripeConnectedAccountId: getString(doc.stripeConnectedAccountId, "") || null,
		stripeCustomerId: getString(doc.stripeCustomerId, "") || null,
	};
}

// Helper function to create the users collection schema
// You'll need to run this once to set up your Typesense collection
export async function createUsersCollection() {
	const schema = {
		name: "users",
		fields: [
			{ name: "id", type: "string" as const },
			{ name: "email", type: "string" as const },
			{ name: "username", type: "string" as const },
			{ name: "artistName", type: "string" as const },
			{ name: "bio", type: "string" as const, optional: true },
			{ name: "deleted", type: "bool" as const },
			{ name: "unclaimed", type: "bool" as const },
			{ name: "occupations", type: "string[]" as const },
			{ name: "timestamp", type: "string" as const, optional: true },
			{ name: "location", type: "geopoint" as const, optional: true },
			{ name: "location.lat", type: "float" as const, optional: true },
			{ name: "location.lng", type: "float" as const, optional: true },
			{ name: "location.placeId", type: "string" as const, optional: true },
			{
				name: "performerInfo.pressKitUrl",
				type: "string" as const,
				optional: true,
			},
			{
				name: "performerInfo.genres",
				type: "string[]" as const,
				optional: true,
			},
			{ name: "performerInfo.rating", type: "float" as const, optional: true },
			{
				name: "performerInfo.reviewCount",
				type: "int32" as const,
				optional: true,
			},
			{ name: "performerInfo.label", type: "string" as const, optional: true },
			{
				name: "performerInfo.spotifyId",
				type: "string" as const,
				optional: true,
			},
			{
				name: "performerInfo.category",
				type: "string" as const,
				optional: true,
			},
			{ name: "venueInfo.genres", type: "string[]" as const, optional: true },
			{ name: "venueInfo.websiteUrl", type: "string" as const, optional: true },
			{
				name: "venueInfo.bookingEmail",
				type: "string" as const,
				optional: true,
			},
			{
				name: "venueInfo.phoneNumber",
				type: "string" as const,
				optional: true,
			},
			{ name: "venueInfo.autoReply", type: "string" as const, optional: true },
			{ name: "venueInfo.capacity", type: "int32" as const, optional: true },
			{
				name: "venueInfo.idealPerformerProfile",
				type: "string" as const,
				optional: true,
			},
			{ name: "venueInfo.type", type: "string" as const, optional: true },
			{
				name: "venueInfo.productionInfo",
				type: "string" as const,
				optional: true,
			},
			{
				name: "venueInfo.frontOfHouse",
				type: "string" as const,
				optional: true,
			},
			{ name: "venueInfo.monitors", type: "string" as const, optional: true },
			{
				name: "venueInfo.microphones",
				type: "string" as const,
				optional: true,
			},
			{ name: "venueInfo.lights", type: "string" as const, optional: true },
			{
				name: "venueInfo.topPerformerIds",
				type: "string[]" as const,
				optional: true,
			},
			{ name: "bookerInfo.rating", type: "float" as const, optional: true },
			{
				name: "bookerInfo.reviewCount",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.youtubeChannelId",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.tiktokHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.tiktokFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.instagramHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.instagramFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.twitterHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.twitterFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.facebookHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.facebookFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.spotifyUrl",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.soundcloudHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.soundcloudFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.audiusHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.audiusFollowers",
				type: "int32" as const,
				optional: true,
			},
			{
				name: "socialFollowing.twitchHandle",
				type: "string" as const,
				optional: true,
			},
			{
				name: "socialFollowing.twitchFollowers",
				type: "int32" as const,
				optional: true,
			},
			{ name: "profilePicture", type: "string" as const, optional: true },
			{
				name: "stripeConnectedAccountId",
				type: "string" as const,
				optional: true,
			},
			{ name: "stripeCustomerId", type: "string" as const, optional: true },
		],
		default_sorting_field: "artistName",
	};

	try {
		await typesenseClient.collections().create(schema);
		console.log("Users collection created successfully");
	} catch (error) {
		console.error("Error creating users collection:", error);
	}
}

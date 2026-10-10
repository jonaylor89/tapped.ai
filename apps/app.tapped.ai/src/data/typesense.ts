/* eslint-disable sonarjs/no-nested-template-literals */

import Typesense from "typesense";
import type { UserModel } from "@/domain/types/user_model";
import { getUserById } from "./database";

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
const typesenseClient = new Typesense.Client({
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
			include_fields: "id",
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

		const users = await Promise.all(
			(response.hits ?? []).map((hit) => getUserById(String((hit.document as { id: string }).id)))
		);
		return users.filter((user): user is UserModel => user !== null);
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
			include_fields: string;
			per_page: number;
			sort_by?: string;
		} = {
			q: query || "*",
			query_by: "artistName,username,bio,performerInfo.label,venueInfo.type",
			filter_by: filterBy.join(" && "),
			include_fields: "id",
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

		const users = await Promise.all(
			(response.hits ?? []).map((hit) => getUserById(String((hit.document as { id: string }).id)))
		);
		return users.filter((user): user is UserModel => user !== null);
	} catch (e) {
		console.error(e);
		return [];
	}
}

import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { autocompleteCities } from "@/data/places";
import type { BoundingBox, UserSearchOptions } from "@/data/typesense";
import type { UserModel } from "@/domain/types/user_model";
import { QueryProvider } from "./query-provider";

function boundingBoxKey(bb: BoundingBox | null): string {
	if (!bb) return "null";
	return `${bb.ne.lat.toFixed(3)},${bb.ne.lng.toFixed(3)},${bb.sw.lat.toFixed(3)},${bb.sw.lng.toFixed(3)}`;
}

export const useSearch = () => {
	const useVenueData = (boundingBox: BoundingBox | null, options: UserSearchOptions) =>
		useQuery({
			queryKey: ["venues", boundingBoxKey(boundingBox), options.hitsPerPage],
			queryFn: async (): Promise<UserModel[]> => {
				const response = await fetch("/api/search", {
					method: "POST",
					headers: {
						"Content-Type": "application/json",
					},
					body: JSON.stringify({
						type: "venues",
						boundingBox,
						options,
					}),
				});

				if (!response.ok) {
					throw new Error("Failed to fetch venues");
				}

				const data = await response.json();
				return data.results;
			},
		});

	const useSearchData = (query: string, options: UserSearchOptions) =>
		useQuery({
			queryKey: ["users", `${query}-${JSON.stringify(options)}`],
			queryFn: async (): Promise<UserModel[]> => {
				if (
					query === "" &&
					options.lat === undefined &&
					options.lng === undefined &&
					options.minCapacity === undefined &&
					options.genres === undefined &&
					options.maxCapacity === undefined
				) {
					return [];
				}

				const response = await fetch("/api/search", {
					method: "POST",
					headers: {
						"Content-Type": "application/json",
					},
					body: JSON.stringify({
						type: "users",
						query,
						options,
					}),
				});

				if (!response.ok) {
					throw new Error("Failed to fetch users");
				}

				const data = await response.json();
				return data.results;
			},
		});

	const useCityData = (query: string) =>
		useQuery({
			queryKey: ["cities", query],
			queryFn: async () => {
				if (query === "") {
					return [];
				}

				return await autocompleteCities(query);
			},
			// Billed Google Places request; results don't change while the user is searching.
			staleTime: 5 * 60 * 1000,
			refetchOnWindowFocus: false,
		});

	return {
		useVenueData,
		useSearchData,
		useCityData,
	};
};

export function SearchProvider({ children }: { children: ReactNode }) {
	return <QueryProvider>{children}</QueryProvider>;
}

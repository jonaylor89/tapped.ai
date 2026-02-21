"use client";

import { ExternalLink, MapPin } from "lucide-react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useMemo } from "react";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import VenueCard from "@/components/location/VenueCard";
import { Button } from "@/components/ui/button";
import UserCluster from "@/components/user/UserCluster";
import { SearchProvider, useSearch } from "@/context/search";

const VenueMap = dynamic(() => import("@/components/map/map"), {
	ssr: false,
	loading: () => (
		<div className="flex h-[400px] w-full items-center justify-center rounded-lg bg-muted">
			<LoadingSpinner />
		</div>
	),
});

type LocationClientProps = {
	placeId: string;
	cityName: string;
	address: string;
	lat: number;
	lng: number;
};

function LocationContent({ cityName, address, lat, lng }: Omit<LocationClientProps, "placeId">) {
	const { useSearchData } = useSearch();

	const { data: venues, isLoading: venuesLoading } = useSearchData("", {
		hitsPerPage: 50,
		lat,
		lng,
		radius: 25_000,
		occupations: ["venue", "Venue"],
	});

	const { data: performers, isLoading: performersLoading } = useSearchData("", {
		hitsPerPage: 50,
		lat,
		lng,
		radius: 50_000,
		occupationsBlacklist: ["venue", "Venue"],
	});

	const smallVenues = useMemo(() => {
		return (venues ?? []).filter((v) => v.venueInfo?.capacity && v.venueInfo.capacity < 250);
	}, [venues]);

	const mediumVenues = useMemo(() => {
		return (venues ?? []).filter(
			(v) => (v.venueInfo?.capacity ?? 0) >= 250 && (v.venueInfo?.capacity ?? 0) < 750
		);
	}, [venues]);

	const largeVenues = useMemo(() => {
		return (venues ?? []).filter((v) => (v.venueInfo?.capacity ?? 0) >= 750);
	}, [venues]);

	const performersByCategory = useMemo(() => {
		const grouped = (performers ?? []).reduce(
			(acc, performer) => {
				const category = performer.performerInfo?.category ?? "undiscovered";
				if (!acc[category]) acc[category] = [];
				acc[category].push(performer);
				return acc;
			},
			{} as Record<string, typeof performers>
		);
		return grouped;
	}, [performers]);

	return (
		<div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
			<div className="mb-8">
				<h1 className="font-bold text-3xl tracking-tight sm:text-4xl lg:text-5xl">{cityName}</h1>
				<div className="mt-2 flex items-center gap-2 text-muted-foreground">
					<MapPin className="h-4 w-4" />
					<span>{address}</span>
				</div>
			</div>

			<div className="mb-8">
				<div className="relative h-[400px] w-full overflow-hidden rounded-lg">
					<VenueMap lat={lat} lng={lng} zoom={12} />
				</div>
				<div className="mt-4 flex justify-end">
					<Link href={`/map?lat=${lat}&lng=${lng}&zoom=12`}>
						<Button variant="outline" className="gap-2">
							<ExternalLink className="h-4 w-4" />
							Open full map
						</Button>
					</Link>
				</div>
			</div>

			<section className="mb-12">
				<h2 className="mb-6 font-bold text-2xl">Venues in {cityName}</h2>

				{venuesLoading ? (
					<div className="flex justify-center py-8">
						<LoadingSpinner />
					</div>
				) : (venues?.length ?? 0) === 0 ? (
					<p className="text-muted-foreground">No venues found in this area.</p>
				) : (
					<div className="space-y-8">
						{smallVenues.length > 0 && (
							<div>
								<h3 className="mb-4 font-semibold text-lg text-muted-foreground">
									Small Venues (&lt;250 capacity)
								</h3>
								<div className="flex flex-row items-start gap-4 overflow-x-auto pb-4">
									{smallVenues.map((venue) => (
										<VenueCard key={venue.id} venue={venue} />
									))}
								</div>
							</div>
						)}

						{mediumVenues.length > 0 && (
							<div>
								<h3 className="mb-4 font-semibold text-lg text-muted-foreground">
									Medium Venues (250-750 capacity)
								</h3>
								<div className="flex flex-row items-start gap-4 overflow-x-auto pb-4">
									{mediumVenues.map((venue) => (
										<VenueCard key={venue.id} venue={venue} />
									))}
								</div>
							</div>
						)}

						{largeVenues.length > 0 && (
							<div>
								<h3 className="mb-4 font-semibold text-lg text-muted-foreground">
									Large Venues (750+ capacity)
								</h3>
								<div className="flex flex-row items-start gap-4 overflow-x-auto pb-4">
									{largeVenues.map((venue) => (
										<VenueCard key={venue.id} venue={venue} />
									))}
								</div>
							</div>
						)}
					</div>
				)}
			</section>

			<section className="mb-12">
				<h2 className="mb-6 font-bold text-2xl">Performers in {cityName}</h2>

				{performersLoading ? (
					<div className="flex justify-center py-8">
						<LoadingSpinner />
					</div>
				) : (performers?.length ?? 0) === 0 ? (
					<p className="text-muted-foreground">No performers found in this area.</p>
				) : (
					<div className="space-y-6">
						{performersByCategory.legendary && performersByCategory.legendary.length > 0 && (
							<div>
								<h3 className="mb-3 font-semibold text-lg text-muted-foreground">Legendary</h3>
								<UserCluster users={performersByCategory.legendary} />
							</div>
						)}

						{performersByCategory.mainstream && performersByCategory.mainstream.length > 0 && (
							<div>
								<h3 className="mb-3 font-semibold text-lg text-muted-foreground">Mainstream</h3>
								<UserCluster users={performersByCategory.mainstream} />
							</div>
						)}

						{performersByCategory.hometownHero && performersByCategory.hometownHero.length > 0 && (
							<div>
								<h3 className="mb-3 font-semibold text-lg text-muted-foreground">Hometown Hero</h3>
								<UserCluster users={performersByCategory.hometownHero} />
							</div>
						)}

						{performersByCategory.emerging && performersByCategory.emerging.length > 0 && (
							<div>
								<h3 className="mb-3 font-semibold text-lg text-muted-foreground">Emerging</h3>
								<UserCluster users={performersByCategory.emerging} />
							</div>
						)}

						{performersByCategory.undiscovered && performersByCategory.undiscovered.length > 0 && (
							<div>
								<h3 className="mb-3 font-semibold text-lg text-muted-foreground">Undiscovered</h3>
								<UserCluster users={performersByCategory.undiscovered} />
							</div>
						)}
					</div>
				)}
			</section>
		</div>
	);
}

export default function LocationClient(props: LocationClientProps) {
	return (
		<SearchProvider>
			<LocationContent
				cityName={props.cityName}
				address={props.address}
				lat={props.lat}
				lng={props.lng}
			/>
		</SearchProvider>
	);
}

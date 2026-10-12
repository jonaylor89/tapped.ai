import { Copy } from "lucide-react";
import { useMemo } from "react";
import UserCluster from "@/components/user/UserCluster";
import type { UserModel } from "@/domain/types/user_model";
import VenueCard from "../location/VenueCard";
import { Button } from "../ui/button";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "../ui/sheet";
import { useToast } from "../ui/use-toast";

export default function LocationSideSheet({
	lat,
	lng,
	zoom,
	venues,
	performers,
	genres: genreMap,
	performersTruncated,
	isOpen,
	onOpenChange,
}: {
	lat: number;
	lng: number;
	zoom: number;
	venues: UserModel[];
	performers: UserModel[];
	genres: Record<string, number>;
	performersTruncated: boolean;
	isOpen: boolean;
	onOpenChange: () => void;
}) {
	const { toast } = useToast();

	// All data arrives with the viewport bundle; opening this sheet performs no profile reads.

	const GenreChips = useMemo(
		() => (
			<div className="flex flex-wrap gap-1">
				{Object.entries(genreMap)
					.sort(([, a], [, b]) => b - a)
					.slice(0, 10)
					.filter(([, count]) => count > 1)
					.map(([genre]) => {
						return (
							<Button key={genre} variant="outline">
								{genre}
							</Button>
						);
					})}
			</div>
		),
		[genreMap]
	);

	const smallVenues = useMemo(() => {
		if (venues.length === 0) {
			return null;
		}

		return (
			<div className="flex flex-row items-start justify-start space-x-5 overflow-x-auto">
				{venues
					.filter((venue) => venue.venueInfo?.capacity && (venue.venueInfo?.capacity ?? 0) < 250)
					.map((p) => (
						<VenueCard key={p.id} venue={p} />
					))}
			</div>
		);
	}, [venues]);

	const mediumVenues = useMemo(() => {
		if (venues.length === 0) {
			return null;
		}

		return (
			<div className="flex flex-row items-start justify-start space-x-5 overflow-x-auto">
				{venues
					.filter(
						(venue) =>
							(venue.venueInfo?.capacity ?? 0) >= 250 && (venue.venueInfo?.capacity ?? 0) < 750
					)
					.map((p) => (
						<VenueCard key={p.id} venue={p} />
					))}
			</div>
		);
	}, [venues]);

	const largeVenues = useMemo(() => {
		if (venues.length === 0) {
			return null;
		}

		return (
			<div className="flex flex-row items-start justify-start space-x-5 overflow-x-auto">
				{venues
					.filter((venue) => (venue.venueInfo?.capacity ?? 0) >= 750)
					.map((p) => (
						<VenueCard key={p.id} venue={p} />
					))}
			</div>
		);
	}, [venues]);

	const performersGroupedByCategory = useMemo(() => {
		if (performers.length === 0) {
			return null;
		}

		const grouped = performers.reduce(
			(acc, performer) => {
				const category = performer.performerInfo?.category ?? "undiscovered";

				if (!acc[category]) {
					acc[category] = [];
				}

				acc[category].push(performer);
				return acc;
			},
			{} as Record<string, UserModel[]>
		);

		const undiscovered = grouped.undiscovered ?? [];
		const emerging = grouped.emerging ?? [];
		const hometownHero = grouped.hometownHero ?? [];
		const mainstream = grouped.mainstream ?? [];
		const legendary = grouped.legendary ?? [];

		return (
			<>
				{undiscovered.length > 0 && (
					<div className="py-6">
						<h3 className="font-bold text-lg lg:text-2xl">undiscovered performers</h3>
						<UserCluster users={undiscovered} />
					</div>
				)}
				{emerging.length > 0 && (
					<div className="py-6">
						<h3 className="font-bold text-lg lg:text-2xl">emerging performers</h3>
						<UserCluster users={emerging} />
					</div>
				)}
				{hometownHero.length > 0 && (
					<div className="py-6">
						<h3 className="font-bold text-lg lg:text-2xl">hometown hero performers</h3>
						<UserCluster users={hometownHero} />
					</div>
				)}
				{mainstream.length > 0 && (
					<div className="py-6">
						<h3 className="font-bold text-lg lg:text-2xl">mainstream performers</h3>
						<UserCluster users={mainstream} />
					</div>
				)}
				{legendary.length > 0 && (
					<div className="py-6">
						<h3 className="font-bold text-lg lg:text-2xl">legendary performers</h3>
						<UserCluster users={legendary} />
					</div>
				)}
			</>
		);
	}, [performers]);

	return (
		<Sheet open={isOpen} onOpenChange={onOpenChange}>
			<SheetContent className="overflow-y-scroll" side="left">
				<SheetTitle className="sr-only">Venues in this area</SheetTitle>
				<SheetDescription className="sr-only">
					Explore venues and performers in the current map area.
				</SheetDescription>
				<div>
					<div className="flex justify-start bg-background/10">
						<Button
							variant="secondary"
							onClick={() => {
								navigator.clipboard.writeText(
									`${window.location.origin}/map?lat=${lat}&lng=${lng}&zoom=${zoom}`
								);

								toast({
									description: "link copied!",
								});
							}}
						>
							<div className="flex flex-row justify-center">
								<p>copy link to location</p>
								<Copy className="ml-2 h-4 w-4" />
							</div>
						</Button>
					</div>
					<div className="flex justify-center py-4">
						<div className="w-full overflow-y-scroll">
							{GenreChips}
							<h3 className="font-bold text-lg lg:text-2xl">small venues</h3>
							{smallVenues}
							<h3 className="font-bold text-lg lg:text-2xl">medium venues</h3>
							{mediumVenues}
							<h3 className="font-bold text-lg lg:text-2xl">large venues</h3>
							{largeVenues}
							{performersTruncated && (
								<p>Showing a limited performer selection. Zoom in for a smaller area.</p>
							)}
							{performersGroupedByCategory}
						</div>
					</div>
				</div>
			</SheetContent>
		</Sheet>
	);
}

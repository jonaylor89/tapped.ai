import NumberFlow from "@number-flow/react";
import { Search } from "lucide-react";
import { type JSX, useMemo } from "react";
import { Button } from "@/components/ui/button";
import { useSearchToggle } from "@/context/use-search-toggle";
import { useStore } from "@/context/use-store";
import { cn } from "@/lib/utils";
import { trackEvent } from "@/utils/tracking";
import { Card } from "../ui/card";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../ui/tooltip";

export default function BottomNavBar({
	onVenueCountClick,
	queryLimit,
	cachedMarkers,
	markers,
	isFetching,
}: {
	onVenueCountClick: () => void;
	queryLimit: number;
	cachedMarkers: React.MutableRefObject<JSX.Element[]>;
	markers: JSX.Element[];
	isFetching: boolean;
}) {
	const searchBar = useStore(useSearchToggle, (state) => state);

	const markersCount = useMemo(() => {
		if (isFetching) {
			return cachedMarkers.current.length;
		}

		return markers.length;
	}, [isFetching, markers, cachedMarkers]);

	return (
		<TooltipProvider>
			<div className="absolute bottom-0 z-40 flex w-full flex-row items-center justify-center">
				<Card className="m-3 flex gap-3 p-1">
					<Tooltip>
						<TooltipTrigger asChild>
							<Button
								variant="outline"
								className={cn("flex gap-1")}
								onClick={() => {
									trackEvent("menu_click");
									onVenueCountClick?.();
								}}
							>
								<span>
									{markersCount === queryLimit && "+"}
									<NumberFlow value={markersCount} />
								</span>
								venues
							</Button>
						</TooltipTrigger>
						<TooltipContent>click to learn more about the venues on the map</TooltipContent>
					</Tooltip>

					<div className="flex gap-1">
						<Tooltip>
							<TooltipTrigger asChild>
								<Button
									size="icon"
									variant="secondary"
									title="search"
									onClick={() => searchBar?.setIsOpen()}
								>
									<Search className="size-3" />
								</Button>
							</TooltipTrigger>
							<TooltipContent>
								search through the biggest live music database for venues, performers, and bookings,
								in the world
							</TooltipContent>
						</Tooltip>
					</div>
				</Card>
			</div>
		</TooltipProvider>
	);
}

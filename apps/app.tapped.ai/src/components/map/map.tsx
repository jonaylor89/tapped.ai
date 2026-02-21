"use client";

import classNames from "classnames";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useTheme } from "next-themes";
import { type JSX, useCallback, useMemo, useRef, useState } from "react";
import {
	FullscreenControl,
	GeolocateControl,
	Map as MapBoxGL,
	type MapEvent,
	Marker,
} from "react-map-gl";
import TappedBanner from "@/components/TappedBanner";
import { useDebounce } from "@/context/debounce";
import { useSearch } from "@/context/search";
import type { BoundingBox } from "@/data/typesense";
import { profileImage } from "@/domain/types/user_model";
import { cn } from "@/lib/utils";
import { trackEvent } from "@/utils/tracking";
import BottomNavBar from "./BottomNavBar";
import LocationSideSheet from "./LocationSideSheet";

const defaultMapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
const mapboxDarkStyle = "mapbox/dark-v11";
const mapboxLightStyle = "mapbox/light-v11";
const LIMIT = 250;

export default function VenueMap({ lat, lng, zoom }: { lat: number; lng: number; zoom: number }) {
	return <VenueMapInner lat={lat} lng={lng} zoom={zoom} />;
}

function VenueMapInner({ lat, lng, zoom }: { lat: number; lng: number; zoom: number }) {
	const [bounds, setBounds] = useState<null | BoundingBox>(null);
	const [sidebarIsOpen, setSidebarIsOpen] = useState(false);
	const { useVenueData } = useSearch();
	const debouncedBounds = useDebounce<null | BoundingBox>(bounds, LIMIT);
	const router = useRouter();
	const { resolvedTheme } = useTheme();

	const { data, isFetching } = useVenueData(debouncedBounds, {
		hitsPerPage: LIMIT,
	});

	const onRender = useCallback((e: MapEvent) => {
		const currentMapBounds = e.target.getBounds();
		if (currentMapBounds === null) {
			return;
		}

		setBounds({
			ne: {
				lat: currentMapBounds.getNorth(),
				lng: currentMapBounds.getWest(),
			},
			sw: {
				lat: currentMapBounds.getSouth(),
				lng: currentMapBounds.getEast(),
			},
		});

		// const { lat: newLat, lng: newLng } = e.target.getCenter();
		// const newZoom = e.target.getZoom();
		// setCenter({ lat: newLat, lng: newLng });
		// setZoom(newZoom);
		// router.push(`/map?lat=${newLat}&lng=${newLng}&zoom=${newZoom}`);
	}, []);

	const cachedMarkers = useRef<JSX.Element[]>([]);

	const markers = useMemo(() => {
		if (isFetching) {
			return cachedMarkers.current;
		}

		const newMarkers = (data ?? [])
			.map((venue) => {
				const lat = venue.location?.lat ?? null;
				const lng = venue.location?.lng ?? null;

				if (lat === null || lng === null) {
					return null;
				}

				const venueCapacity = venue.venueInfo?.capacity ?? 0;
				const imageSrc = profileImage(venue);

				const hasBookingData = venue.venueInfo?.bookingsByDayOfWeek?.some((val) => val !== 0);
				return (
					<Marker
						key={venue.id}
						longitude={lng}
						latitude={lat}
						anchor="center"
						onClick={() => {
							trackEvent("marker_clicked", {
								venueId: venue.id,
							});
							const newPathname = `/map?username=${venue.username}`;
							router.push(newPathname);
						}}
					>
						<div
							className={cn(
								"flex transform flex-row items-center justify-center rounded-xl bg-background px-1 py-1 shadow-lg transition-all duration-200 ease-in-out hover:scale-105 hover:cursor-pointer",
								hasBookingData
									? "border-2 border-yellow-500 border-dotted"
									: "border-background border-none"
							)}
						>
							<div className="relative h-[22px] w-[22px]">
								<Image
									src={imageSrc}
									alt="venue profile picture"
									className="rounded-md"
									style={{ objectFit: "cover", overflow: "hidden" }}
									fill
									sizes="22px"
									unoptimized
								/>
							</div>
							{venueCapacity !== 0 && (
								<p className={classNames("pr-1 pl-1")}>{venueCapacity.toLocaleString()}</p>
							)}
						</div>
					</Marker>
				);
			})
			.filter((x) => x !== null) as JSX.Element[];

		cachedMarkers.current = newMarkers;

		return newMarkers;
	}, [data, router, isFetching]);

	const mapTheme = resolvedTheme === "light" ? mapboxLightStyle : mapboxDarkStyle;
	return (
		<>
			<LocationSideSheet
				venues={data ?? []}
				lat={lat}
				lng={lng}
				zoom={zoom}
				isOpen={sidebarIsOpen}
				onOpenChange={() => setSidebarIsOpen(!sidebarIsOpen)}
			/>
			<TappedBanner />
			<div className="fixed inset-0 z-0 flex h-full w-full flex-col overflow-hidden pt-12">
				<BottomNavBar
					queryLimit={LIMIT}
					markers={markers}
					cachedMarkers={cachedMarkers}
					isFetching={isFetching}
					onVenueCountClick={() => setSidebarIsOpen(!sidebarIsOpen)}
				/>
				<div className="relative flex-1">
					<MapBoxGL
						style={{ height: "100vh !important", width: "100% !important" }}
						initialViewState={{
							latitude: lat,
							longitude: lng,
							zoom: zoom,
							bearing: 0,
							pitch: 0,
						}}
						mapStyle={`mapbox://styles/${mapTheme}`}
						mapboxAccessToken={defaultMapboxToken}
						onRender={onRender}
					>
						<GeolocateControl position="bottom-right" showUserHeading trackUserLocation />
						<FullscreenControl position="bottom-right" />
						{markers}
					</MapBoxGL>
				</div>
			</div>
			{/* <ControlPanel /> */}
		</>
	);
}

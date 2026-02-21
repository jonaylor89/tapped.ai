"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { use } from "react";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import { Button } from "@/components/ui/button";
import { useFeatureFlag } from "@/context/use-feature-flag";

const VenueMap = dynamic(() => import("@/components/map/map"), {
	ssr: false,
	loading: () => (
		<div className="flex min-h-screen w-screen items-center justify-center">
			<LoadingSpinner />
		</div>
	),
});

export default function Page(props: { searchParams: Promise<{ [key: string]: string }> }) {
	const searchParams = use(props.searchParams);
	const { value } = useFeatureFlag("map-city-center");
	const latlng = {
		control: { lat: "40.7128", lng: "-74.0060" },
		los_angles: { lat: "34.052235", lng: "-118.243683" },
		chicago: { lat: "41.878113", lng: "-87.629799" },
		miami: { lat: "25.761681", lng: "-80.191788" },
		san_francisco: { lat: "37.774929", lng: "-122.419418" },
		atlanta: { lat: "33.749001", lng: "-84.387978" },
	};

	const lat = searchParams.lat ?? latlng[value as keyof typeof latlng]?.lat ?? "40.7128";
	const lng = searchParams.lng ?? latlng[value as keyof typeof latlng]?.lng ?? "-74.0060";
	const zoom = searchParams.zoom ?? "11.5";
	const parsedLat = Number.parseFloat(lat);
	const intLat = Number.isNaN(parsedLat) ? 40.7128 : parsedLat;
	const parsedLng = Number.parseFloat(lng);
	const intLng = Number.isNaN(parsedLng) ? -74.006 : parsedLng;
	const parsedZoom = Number.parseFloat(zoom);
	const numZoom = Number.isNaN(parsedZoom) ? 11.5 : parsedZoom;

	return (
		<>
			<div className="h-screen">
				<VenueMap lat={intLat} lng={intLng} zoom={numZoom} />
			</div>
			<div className="no-scroll bottom-0 z-40 hidden w-full md:absolute">
				<div className="flex flex-row items-center justify-center">
					<p className="text-center text-sm">
						© {new Date().getFullYear()} Tapped Industries Inc. All rights reserved.
					</p>
					<Button variant="link">
						<Link href="https://tapped.ai/privacy" target="_blank" rel="noreferrer noopener">
							privacy policy
						</Link>
					</Button>
					<Button variant="link">
						<Link href="https://tapped.ai/terms" target="_blank" rel="noreferrer noopener">
							terms of service
						</Link>
					</Button>
				</div>
			</div>
		</>
	);
}

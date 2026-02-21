import type { Metadata, ResolvingMetadata } from "next";
import { notFound } from "next/navigation";
import Footer from "@/components/Footer";
import { getPlaceById } from "@/data/places";
import type { PlaceData } from "@/domain/types/place_data";
import LocationClient from "./LocationClient";

type Props = {
	params: Promise<{ placeId: string }>;
	searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
};

function getCityName(place: PlaceData): string {
	const locality = place.addressComponents.find((c) => c.types.includes("locality"));
	if (locality) return locality.longName;

	const adminArea = place.addressComponents.find((c) =>
		c.types.includes("administrative_area_level_1")
	);
	if (adminArea) return adminArea.longName;

	return place.shortFormattedAddress.split(",")[0] ?? "Location";
}

export async function generateMetadata(
	props: Props,
	_parent: ResolvingMetadata
): Promise<Metadata> {
	const params = await props.params;
	const metadataBase = "https://tapped.ai";

	try {
		const place = await getPlaceById(params.placeId);
		const cityName = getCityName(place);

		return {
			metadataBase: new URL(metadataBase),
			title: `Venues & Performers in ${cityName} | tapped ai`,
			description: `Discover live music venues and performers in ${cityName}. Find the perfect venue or artist for your next show.`,
			openGraph: {
				type: "website",
				url: `${metadataBase}/location/${params.placeId}`,
				title: `Venues & Performers in ${cityName}`,
				description: `Discover live music venues and performers in ${cityName}`,
				siteName: "tapped ai",
				images: [{ url: `${metadataBase}/og.png` }],
			},
			twitter: {
				card: "summary_large_image",
				site: "@tappedx",
				title: `Venues & Performers in ${cityName}`,
				description: `Discover live music venues and performers in ${cityName}`,
				images: `${metadataBase}/og.png`,
			},
		};
	} catch (e) {
		console.error(e);
		return {
			metadataBase: new URL(metadataBase),
			title: "Location | tapped ai",
			description: "Discover venues and performers near you",
			openGraph: {
				type: "website",
				url: metadataBase,
				title: "tapped ai",
				description: "Discover venues and performers near you",
				siteName: "tapped ai",
				images: [{ url: `${metadataBase}/og.png` }],
			},
			twitter: {
				card: "summary_large_image",
				site: "@tappedx",
				title: "tapped ai",
				description: "Discover venues and performers near you",
				images: `${metadataBase}/og.png`,
			},
		};
	}
}

export default async function Page(props: Props) {
	const params = await props.params;

	let place: PlaceData;
	try {
		place = await getPlaceById(params.placeId);
	} catch (e) {
		console.error(e);
		notFound();
	}

	const cityName = getCityName(place);

	return (
		<div className="min-h-screen">
			<LocationClient
				placeId={params.placeId}
				cityName={cityName}
				address={place.shortFormattedAddress}
				lat={place.lat}
				lng={place.lng}
			/>
			<Footer />
		</div>
	);
}

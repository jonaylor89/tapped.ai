/** `GET https://api.tapped.ai/app/v1/places/autocomplete` */
export type PlacePrediction = {
	placeId: string;
	fullText: string;
	primaryText: string;
	secondaryText: string;
};

/** `GET https://api.tapped.ai/app/v1/places/:placeId` */
export type PlaceData = {
	placeId: string;
	name: string | null;
	shortFormattedAddress: string;
	lat: number;
	lng: number;
	locality: string | null;
	photoNames: string[];
	addressComponents: {
		longText: string | null;
		shortText: string | null;
		types: string[];
	}[];
};

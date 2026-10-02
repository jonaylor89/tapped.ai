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

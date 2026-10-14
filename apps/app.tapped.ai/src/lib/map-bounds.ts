import type { BoundingBox } from "@/data/search";

type MapBounds = {
	getNorth(): number;
	getSouth(): number;
	getEast(): number;
	getWest(): number;
};

function longitudeInRange(longitude: number): number {
	if (longitude >= -180 && longitude <= 180) return longitude;
	return ((((longitude + 180) % 360) + 360) % 360) - 180;
}

/** Mapbox can report longitudes beyond ±180 when displaying wrapped world copies. */
export function venueSearchBounds(bounds: MapBounds): BoundingBox {
	const west = bounds.getWest();
	const east = bounds.getEast();
	const wholeWorld = east - west >= 360;
	return {
		sw: {
			lat: bounds.getSouth(),
			lng: wholeWorld ? -180 : longitudeInRange(west),
		},
		ne: {
			lat: bounds.getNorth(),
			lng: wholeWorld ? 180 : longitudeInRange(east),
		},
	};
}

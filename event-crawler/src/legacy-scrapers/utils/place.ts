import { encodeBase32 } from "geohashing";
import { googlePlacesApiKey } from "../firebase";
import fetch from "node-fetch";

const geohashForLocation = ([lat, lng]: [number, number]) => {
  const hash = encodeBase32(lat, lng);
  return hash;
};

export const searchPlaces = async (
  q: string,
): Promise<
  {
    id: string;
    name: string;
    formattedAddress: string;
    latitude: number;
    longitude: number;
    geohash: string;
  }[]
> => {
  const res = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": googlePlacesApiKey,
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.location",
      },
      body: JSON.stringify({
        textQuery: q,
      }),
    },
  );

  const json = (await res.json()) as {
    places?: {
      id: string;
      displayName: { text: string };
      formattedAddress: string;
      location: { latitude: number; longitude: number };
    }[];
    error?: {
      code: number;
      message: string;
      status: string;
    };
  };

  if (json.error !== undefined) {
    console.log({ error: json.error });
    return [];
  }

  const places = json.places?.map((place) => {
    const { id, displayName, formattedAddress, location } = place;

    const { text: name } = displayName;
    const { latitude, longitude } = location;
    const geohash = geohashForLocation([latitude, longitude]);
    return {
      id,
      name,
      formattedAddress,
      latitude,
      longitude,
      geohash,
    };
  });

  return places ?? [];
};

/* eslint-disable import/no-unresolved */
import * as functions from "firebase-functions";

export const transformLocationPayloadForSearch = functions.https.onCall((data) => {
  const { location, ...rest } = data;
  if (!location) {
    return rest;
  }

  const { lat, lng } = location;

  const payload: Record<string, any> = {
    location,
    ...rest,
  };

  if (lat !== undefined && lat !== null && lng !== undefined && lng !== null) {
    payload._geoloc = { lat, lng };
  }

  return payload;
});

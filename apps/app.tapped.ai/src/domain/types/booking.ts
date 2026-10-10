import type { Option } from "./option";
import type { UserModel } from "./user_model";

export type Booking = {
  id: string;
  serviceId: Option<string>;
  name: string;
  note: string;
  requesterId?: string | null;
  requesteeId: string;
  status: "pending" | "confirmed" | "canceled";
  rate: number;
  location: Location;
  startTime: Date;
  endTime: Date;
  timestamp: Date;
  flierUrl: Option<string>;
  eventUrl: Option<string>;
  venueId: Option<string>;
  referenceEventId: Option<string>;
};

export const bookingImage = (booking: Booking, user: Option<UserModel>): string => {
  if (booking === null) {
    return defaultImage();
  }

  const flierUrl = booking.flierUrl;
  if (flierUrl !== null && flierUrl !== undefined) {
    return flierUrl;
  }

  const pfp = user?.profilePicture;
  if (pfp === null || pfp === undefined) {
    return defaultImage(user?.id);
  }

  return pfp;
};

const defaultImage = (id: Option<string> = null): string => {
  const defaultImages = [
    "/images/default_images/bob.jpg",
    "/images/default_images/daftpunk.jpg",
    "/images/default_images/deadmau5.jpg",
    "/images/default_images/kanye.jpg",
    "/images/default_images/skrillex.jpg",
  ];

  const length = id?.length ?? 0;

  const index = length % defaultImages.length;
  return defaultImages[index];
};

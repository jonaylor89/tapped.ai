export type Opportunity = {
  id: string;
  userId: string;
  title: string;
  description: string;
  flierUrl?: string;
  location: {
    placeId: string;
    lat: number;
    lng: number;
  };
  timestamp: Date;
  startTime: Date;
  endTime: Date;
  deadline?: Date;
  isPaid: boolean;
  genres?: string[];
  venueId?: string | null;
  referenceEventId?: string | null;
};

export const opImage = (opportunity: Opportunity) => {
  if (opportunity.flierUrl !== undefined && opportunity.flierUrl !== null && opportunity.flierUrl !== "") {
    return opportunity.flierUrl;
  }

  return "/images/performance_placeholder.jpg";
};

export type Review = {
	id: string;
	bookerId: string;
	performerId: string;
	bookingId: string;
	timestamp: Date;
	overallRating: number;
	overallReview: string;
	type: "performer" | "booker";
};

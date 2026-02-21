"use client";

import { use, useEffect, useState } from "react";
import ReviewTile from "@/components/profile/ReviewTile";
import { getReviewsByPerformerId } from "@/data/database";
import type { Review } from "@/domain/types/review";

export default function Reviews(props: { params: Promise<{ userid: string }> }) {
	const params = use(props.params);
	const userId = params.userid;

	const [loading, setLoading] = useState(true);
	const [reviews, setReviews] = useState<Review[]>([]);

	useEffect(() => {
		const fetchReviews = async () => {
			if (typeof userId !== "string") {
				return;
			}

			// get reviews
			const reviews = await getReviewsByPerformerId(userId);
			// set reviews
			setReviews(reviews);
			setLoading(false);
		};
		fetchReviews();
	}, [userId]);

	if (loading) {
		return (
			<div className="flex min-h-screen items-center justify-center">
				<p>fetching reviews... </p>
			</div>
		);
	}

	if (reviews.length === 0) {
		return (
			<div className="flex min-h-screen items-center justify-center">
				<p>no reviews</p>
			</div>
		);
	}

	return (
		<div className="md:flex md:justify-center">
			<div className="px-6 py-4 md:w-1/2">
				<h1 className="font-extrabold text-4xl">reviews</h1>
				<div className="h-4" />
				{reviews.map((review) => (
					<div key={review.id} className="py-4">
						<ReviewTile review={review} />
					</div>
				))}
				<div className="h-4" />
				<div className="flex items-center justify-center">
					<p className="font-thin text-gray-500 text-xs">end of list</p>
				</div>
			</div>
		</div>
	);
}

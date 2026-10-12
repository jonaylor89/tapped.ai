import { useEffect, useState } from "react";
import UserTile from "@/components/user/UserTile";
import { getCachedUserById, getUserById } from "@/data/database";
import type { Review } from "@/domain/types/review";
import type { UserModel } from "@/domain/types/user_model";

export default function ReviewTile({ review }: { review: Review }) {
	const [reviewer, setReviewer] = useState<UserModel | null>(null);

	const reviewerId = review.type === "booker" ? review.performerId : review.bookerId;
	useEffect(() => {
		let active = true;
		setReviewer(getCachedUserById(reviewerId));
		void getUserById(reviewerId)
			.then((user) => {
				if (active) setReviewer(user ?? null);
			})
			.catch(() => {});
		return () => {
			active = false;
		};
	}, [reviewerId]);

	return (
		<div className="rounded-xl bg-card p-4">
			<UserTile user={reviewer} />
			<div className="h-2" />
			<p>{review.overallReview}</p>
		</div>
	);
}

import type { Review } from "@/domain/types/review";
import type { UserModel } from "@/domain/types/user_model";
import UserTile from "@/components/user/UserTile";

export default function ReviewTileServer({
	review,
	reviewer,
}: {
	review: Review;
	reviewer: UserModel | null;
}) {
	return (
		<div className="rounded-xl bg-card p-4">
			<UserTile user={reviewer} />
			<div className="h-2" />
			<p>{review.overallReview}</p>
		</div>
	);
}

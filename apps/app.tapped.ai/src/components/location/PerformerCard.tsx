import Image from "next/image";
import { profileImage, type UserModel } from "@/domain/types/user_model";

export default function PerformerCard({ performer }: { performer: UserModel }) {
	const pfp = profileImage(performer);
	return (
		<div className="flex flex-col items-start">
			<div className="relative h-32 w-24 rounded-lg bg-card">
				<Image
					className="h-24 w-24 rounded-lg"
					src={pfp}
					alt={performer.artistName ?? performer.username}
					style={{ objectFit: "cover" }}
					fill
				/>
			</div>
			<p className="mt-2 font-semibold text-sm">{performer.artistName ?? performer.username}</p>
		</div>
	);
}

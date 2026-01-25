import Image from "next/image";
import Link from "next/link";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { Skeleton } from "./ui/skeleton";

export default function UserTile({ user }: { user: UserModel | null }) {
	if (user === null) {
		return <Skeleton />;
	}

	const imageSrc = profileImage(user);

	return (
		<Link href={`/u/${user.username}`}>
			<div className="flex flex-row items-center">
				<div className="relative h-12 w-12 overflow-hidden rounded-full">
					<Image
						src={imageSrc}
						alt={`${user.artistName} profile picture`}
						fill
						style={{
							objectFit: "cover",
							objectPosition: "center",
						}}
					/>
				</div>
				<div className="ml-4">
					<h3 className="line-clamp-1 overflow-hidden text-ellipsis font-bold text-xl">
						{user.artistName}
					</h3>
					<p className="line-clamp-1 overflow-hidden text-ellipsis text-gray-500 text-sm">
						@{user.username}
					</p>
				</div>
			</div>
		</Link>
	);
}

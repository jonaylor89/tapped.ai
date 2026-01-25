import Link from "next/link";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { profileImage, type UserModel } from "@/domain/types/user_model";

export default function UserAvatarList({ users }: { users: UserModel[] }) {
	if (users.length === 0) {
		return null;
	}

	return (
		<div className="flex -space-x-3 overflow-y-scroll *:ring *:ring-white">
			{users.map((user) => (
				<Link
					key={user.id}
					target="_blank"
					rel="noreferrer noopener"
					href={`/u/${user.username}`}
					className="flex items-center justify-center rounded-full transition-transform duration-200 ease-in-out hover:scale-105"
				>
					<Avatar key={user.id}>
						<AvatarImage src={profileImage(user)} alt={user.username} />
						<AvatarFallback>TP</AvatarFallback>
					</Avatar>
				</Link>
			))}
		</div>
	);
}

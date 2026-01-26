import Image from "next/image";
import Link from "next/link";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { Button } from "@/components/ui/button";

export default function UserChipServer({ user }: { user: UserModel }) {
	const imageSrc = profileImage(user);

	return (
		<Link href={`/u/${user.username}`}>
			<Button variant={"outline"} asChild>
				<span className="flex flex-row items-center justify-start">
					<span className="relative h-6 w-6 rounded-xl bg-card">
						<Image
							src={imageSrc}
							alt="performer profile picture"
							className="rounded-xl"
							style={{ objectFit: "cover", overflow: "hidden" }}
							fill
						/>
					</span>
					<span className="p-1 md:p-2">{user.artistName ?? user.username}</span>
				</span>
			</Button>
		</Link>
	);
}

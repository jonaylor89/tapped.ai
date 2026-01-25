import Image from "next/image";
import { usePathname, useRouter } from "next/navigation";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { Button } from "./ui/button";

export default function UserChip({ user, onClick }: { user: UserModel; onClick?: () => void }) {
	const router = useRouter();
	const pathname = usePathname();
	const imageSrc = profileImage(user);

	return (
		<Button
			variant={"outline"}
			onClick={() => {
				onClick?.();
				const newSearchParams = `username=${user.username}`;
				const newPathname = pathname.includes("?")
					? `${pathname}&${newSearchParams}`
					: `${pathname}?${newSearchParams}`;
				router.push(newPathname);
			}}
		>
			<div className="flex flex-row items-center justify-start">
				<div className="relative h-6 w-6 rounded-xl bg-card">
					<Image
						src={imageSrc}
						alt="performer profile picture"
						className="rounded-xl"
						style={{ objectFit: "cover", overflow: "hidden" }}
						fill
					/>
				</div>
				<p className="p-1 md:p-2">{user.artistName ?? user.username}</p>
			</div>
		</Button>
	);
}

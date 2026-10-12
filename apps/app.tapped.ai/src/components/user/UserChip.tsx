import { usePathname, useRouter, useSearchParams } from "next/navigation";
import QueuedImage from "@/components/QueuedImage";
import { Button } from "@/components/ui/button";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { useProfileIntent } from "@/hooks/use-profile-intent";

export default function UserChip({ user, onClick }: { user: UserModel; onClick?: () => void }) {
	const router = useRouter();
	const pathname = usePathname();
	const searchParams = useSearchParams();
	const imageSrc = profileImage(user);
	const intent = useProfileIntent(user.id);

	return (
		<Button
			{...intent}
			variant={"outline"}
			onClick={() => {
				onClick?.();
				const params = new URLSearchParams(searchParams.toString());
				params.set("username", user.username);
				router.push(`${pathname}?${params}`);
			}}
		>
			<div className="flex flex-row items-center justify-start">
				<div className="relative h-6 w-6 rounded-xl bg-card">
					<QueuedImage
						src={imageSrc}
						alt="performer profile picture"
						className="rounded-xl object-cover"
						sizes="24px"
					/>
				</div>
				<p className="p-1 md:p-2">{user.artistName ?? user.username}</p>
			</div>
		</Button>
	);
}

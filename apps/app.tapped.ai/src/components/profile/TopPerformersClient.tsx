"use client";

import Image from "next/image";
import Link from "next/link";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { trackEvent } from "@/utils/tracking";
import { Button } from "../ui/button";

export default function TopPerformersClient({ users }: { users: UserModel[] }) {
	return (
		<div className="flex flex-wrap gap-1">
			{users.map((user) => (
				<Link
					key={user.id}
					href={`/u/${user.username}`}
					onClick={() => {
						trackEvent("top_performer_click", {
							performerId: user.id,
						});
					}}
				>
					<Button variant={"outline"} asChild>
						<span className="flex flex-row items-center justify-start">
							<span className="relative h-6 w-6 rounded-xl bg-card">
								<Image
									src={profileImage(user)}
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
			))}
		</div>
	);
}

"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import QueuedImage from "@/components/QueuedImage";
import { profileImage, type UserModel } from "@/domain/types/user_model";
import { useProfileIntent } from "@/hooks/use-profile-intent";

export default function VenueCard({ venue }: { venue: UserModel }) {
	const pathname = usePathname();
	const searchParams = useSearchParams();
	const createQueryString = useCallback(
		(name: string, value: string) => {
			const params = new URLSearchParams(searchParams.toString());
			params.set(name, value);

			return params.toString();
		},
		[searchParams]
	);

	const pfp = profileImage(venue);
	const intent = useProfileIntent(venue.id);
	return (
		<Link {...intent} href={`${pathname}?${createQueryString("username", venue.username)}`}>
			<div className="group flex flex-col items-start rounded-lg">
				<div className="relative aspect-square h-32 w-32 overflow-hidden rounded-lg bg-card">
					<QueuedImage
						className="aspect-square rounded-lg object-cover transition-all duration-150 ease-in-out group-hover:scale-105"
						src={pfp}
						alt={venue.artistName ?? venue.username}
						sizes="128px"
					/>
				</div>
				<p className="line-clamp-2 text-ellipsis font-bold font-semibold text-sm">
					{venue.artistName ?? venue.username}
				</p>
			</div>
		</Link>
	);
}

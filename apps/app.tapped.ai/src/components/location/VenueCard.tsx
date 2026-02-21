"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { profileImage, type UserModel } from "@/domain/types/user_model";

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
	return (
		<Link href={`${pathname}?${createQueryString("username", venue.username)}`}>
			<div className="group flex flex-col items-start rounded-lg">
				<div className="relative aspect-square h-32 w-32 overflow-hidden rounded-lg bg-card">
					<Image
						className="aspect-square rounded-lg transition-all duration-150 ease-in-out group-hover:scale-105"
						src={pfp}
						alt={venue.artistName ?? venue.username}
						style={{ objectFit: "cover" }}
						fill
					/>
				</div>
				<p className="line-clamp-2 text-ellipsis font-bold font-semibold text-sm">
					{venue.artistName ?? venue.username}
				</p>
			</div>
		</Link>
	);
}

import { BadgeCheck } from "lucide-react";
import Image from "next/image";
import { useEffect, useState } from "react";
import { isVerified } from "@/data/database";
import { profileImage, type UserModel, userAudienceSize } from "@/domain/types/user_model";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../ui/tooltip";

function getSubtitle(hit: UserModel): string {
	const capacity = hit.venueInfo?.capacity ?? null;
	const totalFollowing = userAudienceSize(hit);
	const category = hit.performerInfo?.category ?? null;

	if (capacity === null && category === null) {
		return totalFollowing === 0
			? `@${hit.username}`
			: `${totalFollowing.toLocaleString()} followers`;
	}

	if (capacity === null && category !== null) {
		return `${category} performer`;
	}

	if (capacity === null) {
		return `@${hit.username}`;
	}

	return `${capacity.toLocaleString()} capacity venue`;
}

export function Hit({ hit, onClick }: { hit: UserModel; onClick: () => void }) {
	const imageSrc = profileImage(hit);
	const subtitle = getSubtitle(hit);

	const [verified, setVerified] = useState(false);
	useEffect(() => {
		const getIfVerified = async () => {
			const res = await isVerified(hit.id);
			setVerified(res);
		};

		getIfVerified();
	}, [hit.id]);

	return (
		<button type="button" onClick={onClick}>
			<div className="py-px">
				<div className="my-1 flex w-full flex-row items-center justify-start rounded-xl bg-card px-4 py-3 transition-all duration-150 ease-in-out hover:scale-105">
					<div className="pr-2 pl-1">
						<div className="relative h-[42px] w-[42px]">
							<Image
								src={imageSrc}
								alt="user profile picture"
								fill
								className="rounded-full"
								style={{ objectFit: "cover", overflow: "hidden" }}
							/>
						</div>
					</div>
					<div className="flex w-full flex-1 flex-col items-start justify-center overflow-hidden">
						<h1 className="line-clamp-1 overflow-hidden text-ellipsis text-start font-bold text-xl">
							{(hit.artistName ?? hit.username)?.trim()}
							{verified && (
								<span className="inline">
									<TooltipProvider disableHoverableContent>
										<Tooltip>
											<TooltipTrigger>
												<BadgeCheck className="h-4 w-4" />
											</TooltipTrigger>
											<TooltipContent side="right" align="start" alignOffset={2}>
												verified
											</TooltipContent>
										</Tooltip>
									</TooltipProvider>
								</span>
							)}
						</h1>
						<p className="line-clamp-1 overflow-hidden text-ellipsis text-start text-gray-400 text-sm">
							{subtitle}
						</p>
					</div>
				</div>
			</div>
		</button>
	);
}

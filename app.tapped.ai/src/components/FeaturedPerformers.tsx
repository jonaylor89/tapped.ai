"use client";

import { Dices } from "lucide-react";
import { useMemo, useState } from "react";
import { useHotkeys } from "react-hotkeys-hook";
import type { UserModel } from "@/domain/types/user_model";
import { trackEvent } from "@/utils/tracking";
import UserChip from "@/components/user/UserChip";
import { Button } from "./ui/button";

function samplePerformers(performers: UserModel[], count = 10): UserModel[] {
	return [...performers].sort(() => 0.5 - Math.random()).slice(0, count);
}

export default function FeaturedPerformers({ performers }: { performers: UserModel[] }) {
	const initialSample = useMemo(() => samplePerformers(performers), [performers]);
	const [sampledPerformers, setSampledPerformers] = useState<UserModel[]>(initialSample);

	useHotkeys(
		"space",
		() => {
			setSampledPerformers(samplePerformers(performers));
		},
		{ preventDefault: true }
	);

	return (
		<div className="my-6 flex flex-wrap gap-1">
			{sampledPerformers.map((performer) => (
				<UserChip
					key={performer.id}
					user={performer}
					onClick={() => {
						trackEvent("featured_performer_click", { performer_id: performer.id });
					}}
				/>
			))}
			<Button
				variant={"outline"}
				onClick={() => {
					setSampledPerformers(samplePerformers(performers));
				}}
			>
				<div className="flex flex-row items-center justify-start">
					<div className="relative h-6 w-6 rounded-xl bg-card">
						<Dices className="h-6 w-6" />
					</div>
					<p className="p-1 md:p-2">show more</p>
				</div>
			</Button>
		</div>
	);
}

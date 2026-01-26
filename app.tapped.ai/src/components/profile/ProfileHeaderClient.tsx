"use client";

import dynamic from "next/dynamic";
import { useTheme } from "next-themes";
import { type PerformerCategory, performerScore, type UserModel } from "@/domain/types/user_model";
import { trackEvent } from "@/utils/tracking";
import { Card } from "../ui/card";
import { useToast } from "../ui/use-toast";

const GaugeComponent = dynamic(() => import("react-gauge-component"), {
	ssr: false,
	loading: () => <div className="h-[200px] w-full animate-pulse bg-muted rounded-md" />,
});

export default function ProfileHeaderClient({
	user,
	category,
}: {
	user: UserModel;
	category: PerformerCategory;
}) {
	const { resolvedTheme } = useTheme();
	const { toast } = useToast();

	return (
		<Card
			className="flex w-full cursor-pointer items-center justify-center transition-all duration-150 ease-in-out hover:scale-103"
			onClick={() => {
				trackEvent("gauge_clicked", {
					performer_id: user.id,
				});
				toast({
					title: `${category} performer`,
					description:
						"performers are ranked based on how big their shows are, how frequent they are, and how they're selling tickets",
				});
			}}
		>
			<GaugeComponent
				value={performerScore(category)}
				type="radial"
				labels={{
					valueLabel: {
						style: {
							color: resolvedTheme === "dark" ? "#FFF" : "#000",
						},
						formatTextValue: () => {
							return `${category}`;
						},
					},
				}}
				arc={{
					colorArray: ["#9E9E9E", "#40C4FF", "#FF9800", "#9C27B0", "#F44336"],
					subArcs: [{ limit: 33 }, { limit: 66 }, { limit: 80 }, { limit: 95 }, { limit: 100 }],
					padding: 0.02,
					width: 0.3,
				}}
				pointer={{
					elastic: true,
					animationDelay: 0,
				}}
			/>
		</Card>
	);
}

import Image from "next/image";
import Link from "next/link";
import type { Opportunity } from "@/domain/types/opportunity";

export default function OpportunityTile({ opportunity }: { opportunity: Opportunity }) {
	const opImage = (() => {
		if (
			opportunity.flierUrl !== undefined &&
			opportunity.flierUrl !== null &&
			opportunity.flierUrl !== ""
		) {
			return opportunity.flierUrl;
		}

		return "/images/performance_placeholder.png";
	})();

	return (
		<Link href={`/opportunity/${opportunity.id}`}>
			<div className="flex h-[350px] w-[320px] transform flex-col justify-between overflow-hidden rounded-xl p-4 transition-all duration-200 ease-in-out hover:scale-105">
				<div className="relative h-[300px] w-[300px]">
					<Image
						src={opImage}
						alt="opportunity flier"
						fill
						className="rounded-xl"
						objectFit="cover"
						style={{}}
					/>
				</div>
				<h1 className="font-bold text-xl">{opportunity.title}</h1>
				<div className="h-2" />
			</div>
		</Link>
	);
}

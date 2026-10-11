"use client";

import QueuedImage from "@/components/QueuedImage";

export default function MapMarkerImage({ src }: { src: string }) {
	return (
		<QueuedImage
			src={src}
			alt="Venue profile"
			sizes="24px"
			className="rounded-full object-cover"
			priority={0}
		/>
	);
}

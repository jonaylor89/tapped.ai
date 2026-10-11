"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { createImageQueue } from "@/lib/image-queue";

const enqueue = createImageQueue(4);

export default function MapMarkerImage({ src }: { src: string }) {
	const [admitted, setAdmitted] = useState<string | null>(null);
	const [failed, setFailed] = useState(false);
	const done = useRef<(() => void) | null>(null);
	useEffect(() => {
		setFailed(false);
		if (src.startsWith("/")) {
			setAdmitted(src);
			return;
		}
		const cancel = enqueue((release) => {
			done.current = release;
			setAdmitted(src);
		});
		return () => {
			done.current = null;
			cancel();
		};
	}, [src]);

	if (admitted !== src || failed) {
		return (
			<span
				className="block h-full w-full rounded-md bg-muted"
				role="img"
				aria-label="Venue image unavailable"
			/>
		);
	}
	return (
		<Image
			src={src}
			alt="venue profile picture"
			className="rounded-md"
			style={{ objectFit: "cover", overflow: "hidden" }}
			fill
			sizes="22px"
			loading="eager"
			onLoad={() => {
				done.current?.();
				done.current = null;
			}}
			onError={() => {
				done.current?.();
				done.current = null;
				setFailed(true);
			}}
		/>
	);
}

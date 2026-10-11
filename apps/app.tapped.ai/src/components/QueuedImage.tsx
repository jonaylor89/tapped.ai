"use client";

import Image, { getImageProps } from "next/image";
import { useEffect, useRef, useState } from "react";
import imageLoader from "@/lib/image-loader";
import { createImageQueue } from "@/lib/image-queue";

// An off-DOM image owns the network slot even if its UI unmounts. Native image requests
// can continue after DOM removal; releasing early would oversubscribe the proxy on a pan.
const enqueue = createImageQueue(4, true);
export default function QueuedImage({
	src,
	alt,
	sizes,
	className,
	priority = 1,
}: {
	src: string;
	alt: string;
	sizes: string;
	className?: string;
	priority?: number;
}) {
	const anchor = useRef<HTMLSpanElement>(null);
	const preloaded = useRef<HTMLImageElement | null>(null);
	const [admitted, setAdmitted] = useState<string | null>(null);
	const [failed, setFailed] = useState(false);
	useEffect(() => {
		let alive = true;
		setFailed(false);
		if (!src.trim()) {
			setFailed(true);
			return;
		}
		if (src.startsWith("/")) {
			setAdmitted(src);
			return;
		}
		let cancel: (() => void) | undefined;
		const start = () => {
			if (cancel) return;
			cancel = enqueue((done) => {
				const image = new window.Image();
				preloaded.current = image;
				const { props } = getImageProps({ src, alt: "", fill: true, sizes, loader: imageLoader });
				image.fetchPriority = priority >= 2 ? "high" : "low";
				image.onload = () => {
					if (alive) setAdmitted(src);
					done();
				};
				image.onerror = () => {
					if (alive) setFailed(true);
					done();
				};
				image.sizes = props.sizes ?? "";
				image.srcset = props.srcSet ?? "";
				image.src = props.src;
			}, priority);
		};
		const observer =
			typeof IntersectionObserver === "undefined"
				? null
				: new IntersectionObserver((entries) => {
						if (entries.some((entry) => entry.isIntersecting)) {
							start();
							observer?.disconnect();
						}
					});
		if (observer && anchor.current) observer.observe(anchor.current);
		else start();
		return () => {
			alive = false;
			observer?.disconnect();
			cancel?.();
			preloaded.current = null;
		};
	}, [src, sizes, priority]);
	return (
		<span ref={anchor} className="absolute inset-0">
			{admitted !== src || failed ? (
				<span
					role="img"
					aria-label={`${alt} ${failed ? "unavailable" : "loading"}`}
					className="absolute inset-0 rounded-full bg-muted"
				/>
			) : (
				<Image
					alt={alt}
					src={src}
					loader={imageLoader}
					fill
					sizes={sizes}
					className={className}
					loading="eager"
					onLoad={() => {
						preloaded.current = null;
					}}
					onError={() => {
						setFailed(true);
						preloaded.current = null;
					}}
				/>
			)}
		</span>
	);
}

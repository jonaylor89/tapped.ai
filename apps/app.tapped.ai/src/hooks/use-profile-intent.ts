"use client";

import { type MouseEvent, useEffect, useRef } from "react";
import { prefetchPublicProfile } from "@/data/database";

export function useProfileIntent(userId: string) {
	const cancel = useRef<(() => void) | null>(null);
	// biome-ignore lint/correctness/useExhaustiveDependencies: cancel a queued intent when this element changes identity as well as on unmount
	useEffect(() => () => cancel.current?.(), [userId]);
	const start = () => {
		cancel.current = prefetchPublicProfile(userId);
	};
	return {
		onMouseEnter: start,
		onFocus: start,
		onMouseLeave: (event: MouseEvent<HTMLElement>) => {
			if (document.activeElement !== event.currentTarget) cancel.current?.();
		},
		onBlur: () => cancel.current?.(),
	};
}

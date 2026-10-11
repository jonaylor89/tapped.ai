"use client";

import TappedSheet from "@/components/TappedSheet";

export default function ClientShell({ children }: { children: React.ReactNode }) {
	return (
		<>
			<TappedSheet />
			{children}
		</>
	);
}

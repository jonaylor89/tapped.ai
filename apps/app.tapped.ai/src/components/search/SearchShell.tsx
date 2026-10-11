"use client";

import { Suspense } from "react";
import { useHotkeys } from "react-hotkeys-hook";
import SearchDialog from "@/components/admin-panel/search-dialog";
import { SearchProvider } from "@/context/search";
import { useSearchToggle } from "@/context/use-search-toggle";

// One global dialog and shortcut handler, regardless of how many search bars a page renders.
export default function SearchShell({ children }: { children: React.ReactNode }) {
	useHotkeys("/", (event) => {
		event.preventDefault();
		useSearchToggle.getState().setIsOpen(true);
	});
	return (
		<SearchProvider>
			<Suspense fallback={null}>
				<SearchDialog />
			</Suspense>
			{children}
		</SearchProvider>
	);
}

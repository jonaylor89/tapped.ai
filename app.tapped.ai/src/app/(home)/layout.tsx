"use client";

import { useHotkeys } from "react-hotkeys-hook";
import SearchDialog from "@/components/admin-panel/search-dialog";
import TappedSheet from "@/components/TappedSheet";
import { SearchProvider } from "@/context/search";
import { useSearchToggle } from "@/context/use-search-toggle";
import { useStore } from "@/context/use-store";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
	const searchBar = useStore(useSearchToggle, (state) => state);

	useHotkeys("/", (e) => {
		e.preventDefault();
		searchBar?.setIsOpen();
	});

	return (
		<>
			<TappedSheet />
			<SearchProvider>
				<SearchDialog />
				<main className="w-full">{children}</main>
			</SearchProvider>
		</>
	);
}

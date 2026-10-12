import { create } from "zustand";

interface useSearchToggleStore {
	isOpen: boolean;
	returnFocusTo: HTMLElement | null;
	setIsOpen: (open?: boolean) => void;
}

// Transient UI state: reopening a browser should not resurrect a modal from localStorage.
export const useSearchToggle = create<useSearchToggleStore>((set) => ({
	isOpen: false,
	returnFocusTo: null,
	setIsOpen: (open) =>
		set((state) => {
			const isOpen = open ?? !state.isOpen;
			return {
				isOpen,
				returnFocusTo:
					isOpen && !state.isOpen && typeof document !== "undefined"
						? (document.activeElement as HTMLElement)
						: state.returnFocusTo,
			};
		}),
}));

"use client";

import { Suspense } from "react";
import useWindowDimensions from "@/utils/window_dimensions";
import UserBottomSheet from "./BottomSheet";
import { LoadingSpinner } from "./LoadingSpinner";
import UserSideSheet from "./UserSideSheet";

export default function TappedSheet() {
	const { width } = useWindowDimensions();
	const screenIsSmall = width < 640;

	return (
		<Suspense
			fallback={
				<div className="flex items-center justify-center">
					<LoadingSpinner />
				</div>
			}
		>
			{screenIsSmall ? <UserBottomSheet /> : <UserSideSheet />}
		</Suspense>
	);
}

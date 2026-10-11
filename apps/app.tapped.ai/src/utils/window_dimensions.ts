import { useEffect, useState } from "react";

function getWindowDimensions() {
	if (typeof window === "undefined") {
		return {
			width: 0,
			height: 0,
		};
	}

	const { innerWidth: width, innerHeight: height } = window;
	return {
		width,
		height,
	};
}

export default function useWindowDimensions() {
	// The server and first browser render must choose the same responsive layout.
	const [windowDimensions, setWindowDimensions] = useState({ width: 0, height: 0 });

	useEffect(() => {
		function handleResize() {
			setWindowDimensions(getWindowDimensions());
		}

		handleResize();
		window.addEventListener("resize", handleResize);
		return () => window.removeEventListener("resize", handleResize);
	}, []);

	return windowDimensions;
}

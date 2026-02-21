import { ArrowRight, Info } from "lucide-react";
import Link from "next/link";

export default function TappedBanner() {
	return (
		<div className="fixed top-0 right-0 left-0 z-50 flex h-14 w-full items-center justify-center bg-gradient-to-r from-blue-600 via-blue-500 to-cyan-500 shadow-lg transition-all duration-300 ease-in-out hover:shadow-xl">
			<Link
				href="/about"
				className="group flex items-center gap-2 rounded-full bg-white/10 px-4 py-1.5 font-semibold text-sm text-white backdrop-blur-sm transition-all hover:scale-105 hover:bg-white/20"
			>
				<Info className="h-4 w-4" />
				<span>Learn more about how Tapped works</span>
				<ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
			</Link>
		</div>
	);
}

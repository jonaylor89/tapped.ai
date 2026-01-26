import FeaturedPerformers from "@/components/FeaturedPerformers";
import SearchBar from "@/components/search/SearchBar";
import UnauthHeader from "@/components/unauth_header";
import { getFeaturedPerformers } from "@/data/database";

export default async function Page() {
	const performers = await getFeaturedPerformers();

	return (
		<>
			<UnauthHeader />
			<div className="flex flex-col items-center px-4 pb-12">
				<div className="mt-40 w-full md:w-3/4">
					<h1 className="mb-4 font-black text-5xl">search live music</h1>
					<SearchBar animatedPlaceholder />
				</div>
				<div className="w-full md:w-3/4">
					<FeaturedPerformers performers={performers} />
				</div>
			</div>
		</>
	);
}

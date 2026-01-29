import type { APIRoute } from "astro";
import { connectSpotify, searchSong } from "@/utils/spotify";

export const POST: APIRoute = async ({ request }) => {
	const { term } = await request.json();

	if (!term) {
		return new Response("Missing search term", { status: 400 });
	}

	const accessToken = await connectSpotify();
	const searchResult = await searchSong(term, accessToken);

	if (!searchResult) {
		return new Response("Not found", { status: 404 });
	}

	return new Response(JSON.stringify({ results: searchResult.slice(0, 10) }), {
		headers: { "Content-Type": "application/json" },
	});
};

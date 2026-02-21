import type { APIRoute } from "astro";
import { checkViral, connectSpotify } from "@/utils/spotify";

export const POST: APIRoute = async ({ request }) => {
	const { id, term } = await request.json();

	const accessToken = await connectSpotify();

	if (id !== undefined && id !== null) {
		const isViral = await checkViral(id, accessToken);
		return new Response(JSON.stringify({ is_viral: isViral }), {
			headers: { "Content-Type": "application/json" },
		});
	}

	const data = decodeURIComponent(term);
	const idArr = data.split(",");
	for (let index = 0; index < idArr.length; index++) {
		idArr[index] = idArr[index].replace(/[^a-z0-9]/gi, "");
	}

	const isViral = await checkViral(idArr, accessToken);

	return new Response(JSON.stringify({ is_viral: isViral }), {
		headers: { "Content-Type": "application/json" },
	});
};

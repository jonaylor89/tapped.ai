import { type NextRequest, NextResponse } from "next/server";
import type { UserModel } from "@/domain/types/user_model"
import {
	type BoundingBox,
	queryUsers,
	queryVenuesInBoundedBox,
	type UserSearchOptions,
} from "@/data/typesense";

export async function POST(request: NextRequest) {
	try {
		const body = await request.json();
		const { type, query, boundingBox, options } = body;

		if (!type) {
			return NextResponse.json({ error: "Search type is required" }, { status: 400 });
		}

		if (!options || typeof options !== "object") {
			return NextResponse.json({ error: "Search options are required" }, { status: 400 });
		}

		let results: UserModel[] | null = null;
		switch (type) {
			case "users":
				if (typeof query !== "string") {
					return NextResponse.json(
						{ error: "Query string is required for user search" },
						{ status: 400 }
					);
				}
				results = await queryUsers(query, options as UserSearchOptions);
				break;

			case "venues":
				results = await queryVenuesInBoundedBox(
					boundingBox as BoundingBox | null,
					options as UserSearchOptions
				);
				break;

			default:
				return NextResponse.json(
					{ error: "Invalid search type. Use 'users' or 'venues'" },
					{ status: 400 }
				);
		}

		return NextResponse.json({ results });
	} catch (error) {
		console.error("Search API error:", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}

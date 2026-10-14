import type { Metadata } from "next";
import { tappedApiUrl } from "@/data/tapped_api";
import AuthorizeClient from "./AuthorizeClient";

// Sign-in and consent for the Tapped MCP server. api.tapped.ai/oauth/authorize validates the
// client's request and sends the browser here with `request` (or `error`); see the API README.
export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Connect to Tapped", robots: { index: false } };

async function authorizationRequest(id: string) {
	const response = await fetch(
		`${tappedApiUrl}/oauth/authorization-requests/${encodeURIComponent(id)}`,
		{ cache: "no-store" }
	);
	if (!response.ok) return null;
	return (await response.json()) as { clientName: string; redirectHost: string };
}

export default async function AuthorizePage({
	searchParams,
}: {
	searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
	const { request, error } = await searchParams;
	const details = typeof request === "string" ? await authorizationRequest(request) : null;
	const problem =
		typeof error === "string"
			? error
			: "This sign-in request expired or is invalid. Start again from your MCP client.";

	return (
		<main className="flex min-h-[80vh] items-center justify-center px-4 py-12">
			<div className="w-full max-w-md rounded-xl border bg-card p-6 text-card-foreground shadow-sm">
				{details && typeof request === "string" ? (
					<AuthorizeClient
						request={request}
						clientName={details.clientName}
						redirectHost={details.redirectHost}
					/>
				) : (
					<>
						<h1 className="font-semibold text-xl">Can't connect to Tapped</h1>
						<p className="mt-2 text-muted-foreground text-sm">{problem}</p>
					</>
				)}
			</div>
		</main>
	);
}

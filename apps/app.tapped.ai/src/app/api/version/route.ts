// Public, non-secret deployment identity for post-deploy verification. No application data.
export const dynamic = "force-dynamic";

export function GET(): Response {
	return Response.json(
		{ commit: process.env.TAPPED_DEPLOY_SHA ?? process.env.VERCEL_GIT_COMMIT_SHA ?? null },
		{ headers: { "Cache-Control": "no-store" } }
	);
}

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/app/api/version/route.ts", import.meta.url), "utf8"), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } });
const { GET, dynamic } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("version exposes only the deployment SHA, never environment/config/application data", async () => {
	const previous = process.env.VERCEL_GIT_COMMIT_SHA;
	const previousOverride = process.env.TAPPED_DEPLOY_SHA;
	try {
		delete process.env.TAPPED_DEPLOY_SHA;
		process.env.VERCEL_GIT_COMMIT_SHA = "a".repeat(40);
		const response = GET();
		assert.equal(dynamic, "force-dynamic");
		assert.equal(response.headers.get("cache-control"), "no-store");
		assert.deepEqual(await response.json(), { commit: "a".repeat(40) });
		process.env.TAPPED_DEPLOY_SHA = "b".repeat(40);
		assert.deepEqual(await GET().json(), { commit: "b".repeat(40) });
		delete process.env.TAPPED_DEPLOY_SHA;
		delete process.env.VERCEL_GIT_COMMIT_SHA;
		assert.deepEqual(await GET().json(), { commit: null });
	} finally {
		if (previous === undefined) delete process.env.VERCEL_GIT_COMMIT_SHA;
		else process.env.VERCEL_GIT_COMMIT_SHA = previous;
		if (previousOverride === undefined) delete process.env.TAPPED_DEPLOY_SHA;
		else process.env.TAPPED_DEPLOY_SHA = previousOverride;
	}
});

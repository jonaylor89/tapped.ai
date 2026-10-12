import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/intent-prefetch.ts", import.meta.url), "utf8"), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } });
const { createIntentPrefetch } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);
const sleep = (ms = 20) => new Promise((r) => setTimeout(r, ms));

test("drive-by hover cancels and last intent wins without starting a request", async () => {
	const calls = [];
	const prefetch = createIntentPrefetch(async (key) => { calls.push(key); }, () => true, 5);
	prefetch("first");
	const cancel = prefetch("second"); cancel();
	await sleep(); assert.deepEqual(calls, []);
	prefetch("third"); await sleep(); assert.deepEqual(calls, ["third"]);
});

test("only one speculative request runs at a time, with bounded waiting intent", async () => {
	const calls = [];
	let release;
	const prefetch = createIntentPrefetch(async (key) => {
		calls.push(key);
		if (key === "active") await new Promise((r) => { release = r; });
	}, () => true, 5);
	prefetch("active"); await sleep();
	prefetch("obsolete"); await sleep();
	prefetch("latest"); await sleep();
	assert.deepEqual(calls, ["active"]);
	release(); await sleep(); assert.deepEqual(calls, ["active", "latest"]);
});

test("save-data/slow/hidden guards and per-minute budget suppress speculative work", async () => {
	let allowed = false;
	const calls = [];
	const prefetch = createIntentPrefetch(async (key) => { calls.push(key); }, () => allowed, 5, 1);
	prefetch("blocked"); await sleep(); assert.deepEqual(calls, []);
	allowed = true;
	prefetch("one"); await sleep();
	prefetch("two"); await sleep(); assert.deepEqual(calls, ["one"]);
});

test("prefetch failures do not break foreground operation or stall the queue", async () => {
	const calls = [];
	const prefetch = createIntentPrefetch(async (key) => { calls.push(key); if (key === "bad") throw new Error("429"); }, () => true, 5);
	prefetch("bad"); await sleep(); prefetch("good"); await sleep();
	assert.deepEqual(calls, ["bad", "good"]);
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/image-queue.ts", import.meta.url), "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { createImageQueue } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("250 cold map thumbnails admit no more than four requests at once", () => {
	const enqueue = createImageQueue(4);
	const completions = [];
	let active = 0;
	let max = 0;
	for (let i = 0; i < 250; i++) enqueue((done) => {
		max = Math.max(max, ++active);
		completions.push(() => { active--; done(); });
	});
	assert.equal(completions.length, 4);
	for (let i = 0; i < 250; i++) completions[i]();
	assert.equal(max, 4);
	assert.equal(active, 0);
	assert.equal(completions.length, 250);
});

test("unmounted queued markers never start, and load/error completion is idempotent", () => {
	const enqueue = createImageQueue(1);
	let done;
	const cancelActive = enqueue((release) => { done = release; });
	const cancelWaiting = enqueue(() => assert.fail("removed marker loaded"));
	cancelWaiting();
	let started = false;
	enqueue((release) => { started = true; release(); });
	cancelActive();
	assert.equal(started, true);
	done();
	cancelActive();
	let works = false;
	enqueue((release) => { works = true; release(); });
	assert.equal(works, true);
});

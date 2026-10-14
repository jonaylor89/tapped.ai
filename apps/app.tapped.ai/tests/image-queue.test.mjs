import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/image-queue.ts", import.meta.url), "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { createImageQueue } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("unlimited mode admits all thumbnails without waiting for an earlier image", () => {
	const enqueue = createImageQueue(Number.POSITIVE_INFINITY, true);
	const completions = [];
	for (let i = 0; i < 1000; i++) {
		enqueue((done) => { completions.push(done); });
	}
	assert.equal(completions.length, 1000);
	for (const done of completions) {
		done();
		done();
	}
	let started = false;
	enqueue((done) => { started = true; done(); });
	assert.equal(started, true);
});

test("invalid image concurrency remains rejected", () => {
	for (const concurrency of [0, -1, 1.5, Number.NaN, Number.NEGATIVE_INFINITY]) {
		assert.throws(() => createImageQueue(concurrency), /Invalid image concurrency/);
	}
});

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

test("selected visible images jump queued markers without interrupting active loads", () => {
	const enqueue = createImageQueue(1);
	let done;
	const order = [];
	enqueue((release) => { order.push("active"); done = release; }, 0);
	enqueue((release) => { order.push("marker"); release(); }, 0);
	enqueue((release) => { order.push("profile"); release(); }, 2);
	enqueue((release) => { order.push("card"); release(); }, 1);
	done();
	assert.deepEqual(order, ["active", "profile", "card", "marker"]);
});

test("a detached native preload retains its slot until network completion", () => {
	const enqueue = createImageQueue(1, true);
	let done;
	const cancel = enqueue((release) => { done = release; });
	let started = false;
	enqueue((release) => { started = true; release(); });
	cancel();
	assert.equal(started, false);
	done();
	assert.equal(started, true);
});

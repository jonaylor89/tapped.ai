import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";

const source = readFileSync(new URL("../src/lib/batch-users.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
	compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { batchUsers, areaPerformerIds } = await import(
	`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`
);

test("145 occurrences are deduplicated before requests, not after", async () => {
	const venues = Array.from({ length: 29 }, () => ({ venueInfo: { topPerformerIds: ["a", "b", "a", "c", "b"] } }));
	const calls = [];
	const result = await batchUsers(areaPerformerIds(venues), async (ids) => {
		calls.push(ids);
		return ids.map((id) => ({ id }));
	});
	assert.deepEqual(calls, [["a", "b", "c"]]);
	assert.deepEqual(result, [{ id: "a" }, { id: "b" }, { id: "c" }]);
	assert.deepEqual(areaPerformerIds([...venues].reverse()), areaPerformerIds(venues));
});

test("145 distinct IDs use three serial batches of at most 50", async () => {
	const ids = Array.from({ length: 145 }, (_, i) => `p${i}`);
	let active = 0;
	let maxActive = 0;
	const sizes = [];
	const result = await batchUsers(ids, async (chunk) => {
		sizes.push(chunk.length);
		maxActive = Math.max(maxActive, ++active);
		await Promise.resolve();
		active--;
		return chunk.map((id) => ({ id }));
	});
	assert.deepEqual(sizes, [50, 50, 45]);
	assert.equal(maxActive, 1);
	assert.deepEqual(result.map((row) => row.id), ids);
});

test("missing/deleted profiles and duplicate/unrequested rows are omitted", async () => {
	assert.deepEqual(await batchUsers(["a", "missing", "a"], async () => [{ id: "a" }, { id: "a" }, { id: "other" }]), [{ id: "a" }]);
	assert.deepEqual(await batchUsers([], async () => assert.fail("no empty requests")), []);
});

test("closing or changing area cancels queued batches and rejects stale results", async () => {
	const controller = new AbortController();
	let calls = 0;
	await assert.rejects(batchUsers(Array.from({ length: 51 }, (_, i) => `${i}`), async (_ids, signal) => {
		assert.equal(signal, controller.signal);
		calls++;
		controller.abort();
		return [{ id: "0" }];
	}, controller.signal), { name: "AbortError" });
	assert.equal(calls, 1);
	await assert.rejects(batchUsers(["a"], async () => assert.fail("already cancelled"), controller.signal), { name: "AbortError" });
});

test("API failure is propagated rather than represented as an empty area", async () => {
	await assert.rejects(batchUsers(["a"], async () => { throw new Error("429"); }), /429/);
});

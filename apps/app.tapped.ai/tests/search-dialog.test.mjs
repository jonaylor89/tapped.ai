import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
import { createRequire } from "node:module";

const read = (path) => readFileSync(new URL(`../src/${path}`, import.meta.url), "utf8");
test("only the global search shell owns the modal and slash shortcut", () => {
	const shell = read("components/search/SearchShell.tsx");
	assert.equal((shell.match(/<SearchDialog\s/g) ?? []).length, 1);
	assert.match(read("app/layout.tsx"), /<SearchShell>/);
	for (const path of ["components/search/SearchBar.tsx", "app/(home)/ClientShell.tsx"]) {
		assert.doesNotMatch(read(path), /SearchDialog|useHotkeys/);
	}
});

test("dialog state changes are explicit/idempotent and never persisted", () => {
	const { outputText } = ts.transpileModule(read("context/use-search-toggle.ts"), {
		compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
	});
	const module = { exports: {} };
	new Function("require", "exports", outputText)(createRequire(import.meta.url), module.exports);
	const store = module.exports.useSearchToggle;
	store.getState().setIsOpen(true);
	store.getState().setIsOpen(true);
	assert.equal(store.getState().isOpen, true);
	store.getState().setIsOpen(false);
	store.getState().setIsOpen(false);
	assert.equal(store.getState().isOpen, false);
	assert.doesNotMatch(read("context/use-search-toggle.ts"), /persist\(/);
});

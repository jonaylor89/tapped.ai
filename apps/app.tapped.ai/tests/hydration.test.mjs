import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import ts from "typescript";

const source = readFileSync(new URL("../src/utils/window_dimensions.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
	compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
});
const module = { exports: {} };
new Function("require", "module", "exports", outputText)(
	createRequire(import.meta.url),
	module,
	module.exports
);
const useWindowDimensions = module.exports.default;

function Probe() {
	const { width, height } = useWindowDimensions();
	return createElement("output", null, `${width},${height}`);
}

test("server and first browser render use identical responsive dimensions", () => {
	const original = globalThis.window;
	try {
		delete globalThis.window;
		const server = renderToStaticMarkup(createElement(Probe));
		for (const width of [375, 1280]) {
			globalThis.window = { innerWidth: width, innerHeight: 800 };
			assert.equal(renderToStaticMarkup(createElement(Probe)), server);
		}
		assert.equal(server, "<output>0,0</output>");
	} finally {
		if (original === undefined) delete globalThis.window;
		else globalThis.window = original;
	}
});

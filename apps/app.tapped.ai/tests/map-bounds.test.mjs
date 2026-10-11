import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";

// Exercise the production TypeScript helper using the existing compiler; no test dependency.
const source = readFileSync(new URL("../src/lib/map-bounds.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
	compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { venueSearchBounds } = await import(
	`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`
);

function bounds(west, south, east, north) {
	return {
		getWest: () => west,
		getSouth: () => south,
		getEast: () => east,
		getNorth: () => north,
	};
}

test("NYC uses west for southwest and east for northeast", () => {
	assert.deepEqual(venueSearchBounds(bounds(-74.08, 40.64, -73.9, 40.8)), {
		sw: { lat: 40.64, lng: -74.08 },
		ne: { lat: 40.8, lng: -73.9 },
	});
});

test("eastern-hemisphere viewport preserves both coordinate axes", () => {
	assert.deepEqual(venueSearchBounds(bounds(12, 51, 14, 53)), {
		sw: { lat: 51, lng: 12 },
		ne: { lat: 53, lng: 14 },
	});
});

test("date-line crossing remains an intentional wrapped interval", () => {
	assert.deepEqual(venueSearchBounds(bounds(170, -10, -170, 10)), {
		sw: { lat: -10, lng: 170 },
		ne: { lat: 10, lng: -170 },
	});
});

test("eastward world copies normalize beyond +180", () => {
	assert.deepEqual(venueSearchBounds(bounds(170, -10, 190, 10)), {
		sw: { lat: -10, lng: 170 },
		ne: { lat: 10, lng: -170 },
	});
});

test("westward world copies normalize beyond -180", () => {
	assert.deepEqual(venueSearchBounds(bounds(-190, -10, -170, 10)), {
		sw: { lat: -10, lng: 170 },
		ne: { lat: 10, lng: -170 },
	});
});

test("viewports spanning a world cover all longitudes rather than collapsing", () => {
	for (const b of [bounds(-180, -80, 180, 80), bounds(-270, -80, 270, 80)]) {
		assert.deepEqual(venueSearchBounds(b), {
			sw: { lat: -80, lng: -180 },
			ne: { lat: 80, lng: 180 },
		});
	}
});

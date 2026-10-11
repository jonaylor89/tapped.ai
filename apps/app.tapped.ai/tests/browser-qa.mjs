// Optional real-Chrome regression suite. Start a production preview and Chrome with :9222 CDP.
// No browser/test dependencies; requires Node 22+ (native WebSocket).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const thumbnail = readFileSync(new URL("../public/images/icon_1024.png", import.meta.url)).toString("base64");

const base = process.env.QA_BASE_URL ?? "http://localhost:3101";
const cdp = process.env.CDP_URL ?? "http://localhost:9222";
const tab = await (await fetch(`${cdp}/json/new?about:blank`, { method: "PUT" })).json();
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((resolve) => ws.addEventListener("open", resolve, { once: true }));
let sequence = 0;
const pending = new Map();
const warnings = [];
const batches = [];
let activeImages = 0;
let maxImages = 0;
let loadedImages = 0;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const call = (method, params = {}) => new Promise((resolve, reject) => {
	const id = ++sequence;
	pending.set(id, { resolve, reject });
	ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) => {
	const response = await call("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
	if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
	return response.result.value;
};
const wait = async (expression) => {
	for (let i = 0; i < 600; i++) {
		if (await evaluate(expression)) return;
		await sleep(100);
	}
	throw new Error(`Timed out: ${expression}`);
};
const venues = Array.from({ length: 250 }, (_, i) => ({
	id: `venue-${i}`, username: `venue-${i}`, artistName: `Venue ${i}`, occupations: ["venue"],
	location: { lat: 40.73 + (i % 10) * 0.001, lng: -73.99 + Math.floor(i / 10) * 0.001 },
	profilePicture: `https://storage.googleapis.com/in-the-loop-306520.appspot.com/qa-thumbnail-${i}.png`,
	venueInfo: { capacity: 100, topPerformerIds: [`p${i % 145}`, `p${i % 145}`] },
}));
const fulfill = (requestId, data, contentType = "application/json") => call("Fetch.fulfillRequest", {
	requestId, responseCode: 200,
	responseHeaders: [{ name: "Content-Type", value: contentType }, { name: "Access-Control-Allow-Origin", value: "*" }],
	body: contentType === "application/json" ? Buffer.from(JSON.stringify(data)).toString("base64") : data,
});
const intercept = async ({ requestId, request }) => {
	const url = new URL(request.url);
	if (url.hostname === "api.mapbox.com" && url.pathname.startsWith("/styles/")) {
		return fulfill(requestId, { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#111" } }] });
	}
	if (["api.mapbox.com", "events.mapbox.com"].includes(url.hostname)) return fulfill(requestId, {});
	if (url.pathname === "/api/search") {
		const { type } = JSON.parse(request.postData);
		return fulfill(requestId, { results: type === "venues" ? venues : [] });
	}
	if (url.searchParams.has("ids")) {
		const ids = url.searchParams.get("ids").split(",");
		batches.push(ids);
		await sleep(80);
		return fulfill(requestId, ids.map((id) => ({ id, username: id, artistName: id, occupations: ["performer"], performerInfo: { category: "undiscovered" } })));
	}
	activeImages++;
	maxImages = Math.max(maxImages, activeImages);
	await sleep(100);
	activeImages--;
	loadedImages++;
	// Known-valid local PNG, delayed to exercise the production thumbnail queue.
	return fulfill(requestId, thumbnail, "image/png");
};
let interceptionError;
ws.addEventListener("message", (event) => {
	const message = JSON.parse(event.data);
	if (message.id) {
		const callback = pending.get(message.id);
		pending.delete(message.id);
		if (message.error) callback?.reject(message.error); else callback?.resolve(message.result);
	} else if (message.method === "Fetch.requestPaused") {
		intercept(message.params).catch((error) => { interceptionError = error; });
	} else if (message.method === "Log.entryAdded") {
		warnings.push(message.params.entry.text);
	} else if (message.method === "Runtime.consoleAPICalled") {
		warnings.push(message.params.args.map((arg) => arg.value ?? arg.description ?? "").join(" "));
	}
});

try {
	await call("Runtime.enable");
	await call("Log.enable");
	await call("Fetch.enable", { patterns: [
		{ urlPattern: "https://api.mapbox.com/*" },
		{ urlPattern: "https://events.mapbox.com/*" },
		{ urlPattern: "*/api/search" },
		{ urlPattern: "*/app/v1/public/data/users?ids=*" },
		{ urlPattern: "*storage.googleapis.com/*/qa-thumbnail-*" },
	] });
	await call("Page.navigate", { url: `${base}/search` });
	await wait('!!document.querySelector("input")');
	await evaluate('document.querySelector("input").focus(); document.querySelector("input").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 1');
	assert.equal(await evaluate('!!document.activeElement.closest("[aria-hidden=true]")'), false);
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent === "Close").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 0');
	assert.equal(await evaluate('document.activeElement.tagName'), "INPUT");
	// Blur the search input before testing the global slash shortcut.
	await evaluate("document.activeElement.blur()");
	await call("Input.dispatchKeyEvent", { type: "keyDown", key: "/", code: "Slash" });
	await call("Input.dispatchKeyEvent", { type: "keyUp", key: "/", code: "Slash" });
	await wait('document.querySelectorAll("[role=dialog]").length === 1');
	await call("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape" });
	await call("Input.dispatchKeyEvent", { type: "keyUp", key: "Escape", code: "Escape" });
	await wait('document.querySelectorAll("[role=dialog]").length === 0');

	await call("Page.navigate", { url: `${base}/map?lat=40.73&lng=-73.99&zoom=12` });
	await wait('document.querySelectorAll(".mapboxgl-marker").length === 250');
	await wait('document.querySelectorAll(".mapboxgl-marker img").length === 250 && Array.from(document.querySelectorAll(".mapboxgl-marker img")).every(img=>img.complete && img.naturalWidth > 0)');
	assert.equal(loadedImages, 250);
	assert.ok(maxImages <= 4, `thumbnail concurrency ${maxImages} > 4`);
	assert.equal(batches.length, 0, "closed area sheet must not fetch performers");
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent.includes("venues")).click()');
	await wait('document.body.textContent.includes("undiscovered performers")');
	assert.deepEqual(batches.map((ids) => ids.length), [50, 50, 45]);
	assert.equal(new Set(batches.flat()).size, 145);
	assert.equal(interceptionError, undefined);
	assert.equal(warnings.some((warning) => /Blocked aria-hidden|retained focus/.test(warning)), false);
	console.log("Chrome QA passed: one dialog, focus restored, slash/Escape, closed-sheet silence, 500 occurrences → 3 batches, 250 images with concurrency ≤4");
} catch (error) {
	console.error({ interceptionError, warnings, loadedImages, maxImages, activeImages, page: await evaluate('({url:location.href,markers:document.querySelectorAll(".mapboxgl-marker").length,text:document.body.innerText.slice(0,300)})') });
	throw error;
} finally {
	ws.close();
	await fetch(`${cdp}/json/close/${tab.id}`);
}

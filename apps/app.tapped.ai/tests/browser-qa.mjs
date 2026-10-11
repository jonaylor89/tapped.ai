// Optional production-preview Chrome/CDP regressions. Node 22+, no browser dependencies.
// API, images and Mapbox use fixtures; this is not production deployment verification.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const mapCss = readFileSync(new URL("../node_modules/mapbox-gl/dist/mapbox-gl.css", import.meta.url)).toString("base64");
const thumbnail = readFileSync(new URL("../public/images/icon_1024.png", import.meta.url)).toString("base64");
const base = process.env.QA_BASE_URL ?? "http://localhost:3101";
const cdp = process.env.CDP_URL ?? "http://localhost:9222";
const tab = await (await fetch(`${cdp}/json/new?about:blank`, { method: "PUT" })).json();
const ws = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((resolve) => ws.addEventListener("open", resolve, { once: true }));
let sequence = 0;
const pending = new Map();
const warnings = [];
const mapRequests = [];
const detailRequests = [];
const profileReads = [];
const deleted = new Set();
let detailDelay = 80;
let failMaps = false;
let activeImages = 0;
let maxImages = 0;
let loadedImages = 0;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const call = (method, params = {}) => new Promise((resolve, reject) => {
	const id = ++sequence; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expression) => {
	const response = await call("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
	if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
	return response.result.value;
};
const wait = async (expression) => {
	for (let i = 0; i < 600; i++) { if (await evaluate(expression)) return; await sleep(100); }
	throw new Error(`Timed out: ${expression}`);
};
const common = { bio: "Public fixture profile", unclaimed: false, deleted: false, bookerInfo: null, performerInfo: null, socialFollowing: null };
const venues = Array.from({ length: 250 }, (_, i) => ({
	...common, id: `venue-${i}`, username: `venue-${i}`, artistName: `Venue ${i}`, occupations: ["venue"],
	location: { lat: 40.73 + (i % 10) * 0.001, lng: -73.99 + Math.floor(i / 10) * 0.001 },
	profilePicture: `https://storage.googleapis.com/in-the-loop-306520.appspot.com/qa-thumbnail-${i}.png`,
	venueInfo: { capacity: 100, genres: ["rock"], topPerformerIds: [`p${i % 145}`, `p${i % 145}`, "missing"] },
}));
const performers = Array.from({ length: 145 }, (_, i) => ({ ...common, id: `p${i}`, username: `p${i}`, artistName: `Performer ${i}`, occupations: ["performer"], performerInfo: { category: "undiscovered", reviewCount: 0 }, venueInfo: null }));
const reviewer = { ...common, id: "qa-reviewer", username: "qa-reviewer", artistName: "Cached reviewer", occupations: ["booker"], venueInfo: null };
const fulfill = (requestId, data, contentType = "application/json", status = 200) => call("Fetch.fulfillRequest", {
	requestId, responseCode: status,
	responseHeaders: [{ name: "Content-Type", value: contentType }, { name: "Access-Control-Allow-Origin", value: "*" }],
	body: contentType === "application/json" ? Buffer.from(JSON.stringify(data)).toString("base64") : data,
});
const intercept = async ({ requestId, request }) => {
	const url = new URL(request.url);
	if (url.hostname === "api.mapbox.com" && url.pathname.endsWith("/mapbox-gl.css")) return fulfill(requestId, mapCss, "text/css");
	if (url.hostname === "api.mapbox.com" && url.pathname.startsWith("/styles/")) return fulfill(requestId, { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#111" } }] });
	if (["api.mapbox.com", "events.mapbox.com"].includes(url.hostname)) return fulfill(requestId, {});
	if (url.pathname === "/api/search") return fulfill(requestId, { results: [] });
	if (url.pathname === "/app/v1/public/map") {
		mapRequests.push(url.search);
		assert.ok(url.searchParams.has("swLat"), "no unbounded initial map search");
		if (failMaps) return fulfill(requestId, { error: "temporary outage" }, "application/json", 503);
		return fulfill(requestId, { venues, performers, genres: { rock: 250 }, venuesTruncated: false, performersTruncated: false });
	}
	const details = url.pathname.match(/\/public\/users\/([^/]+)\/details$/);
	if (details) {
		const id = details[1]; detailRequests.push(id); await sleep(detailDelay);
		if (deleted.has(id)) return fulfill(requestId, { error: "not found" }, "application/json", 404);
		const user = [...venues, ...performers].find((row) => row.id === id);
		const latestReview = id === "venue-0" ? { id: "qa-review", bookerId: reviewer.id, performerId: id, bookingId: "qa-booking", type: "performer", timestamp: "2026-10-11T00:00:00Z", overallRating: 4, overallReview: "A public review" } : null;
		const top = user.venueInfo?.topPerformerIds?.[0];
		const relatedUsers = [...(latestReview ? [reviewer] : []), ...performers.filter((row) => row.id === top)];
		return fulfill(requestId, { user: { ...user, artistName: `Fresh ${user.artistName}` }, bookingCount: 0, bookings: [], latestReview, relatedUsers });
	}
	if (url.pathname.includes("/public/data/users") || url.pathname.includes("/users/username/")) {
		profileReads.push(url.href);
		return fulfill(requestId, { error: "unexpected per-profile read" }, "application/json", 404);
	}
	activeImages++; maxImages = Math.max(maxImages, activeImages);
	await sleep(100); activeImages--; loadedImages++;
	return fulfill(requestId, thumbnail, "image/png");
};
let interceptionError;
ws.addEventListener("message", (event) => {
	const message = JSON.parse(event.data);
	if (message.id) {
		const callback = pending.get(message.id); pending.delete(message.id);
		if (message.error) callback?.reject(message.error); else callback?.resolve(message.result);
	} else if (message.method === "Fetch.requestPaused") intercept(message.params).catch((error) => { interceptionError = error; });
	else if (message.method === "Log.entryAdded") warnings.push(message.params.entry.text);
	else if (message.method === "Runtime.consoleAPICalled") warnings.push(message.params.args.map((arg) => arg.value ?? arg.description ?? "").join(" "));
});

try {
	await call("Runtime.enable"); await call("Log.enable"); await call("Page.enable");
	await call("Page.addScriptToEvaluateOnNewDocument", { source: 'window.__qaConnection={saveData:false,effectiveType:"4g"};Object.defineProperty(navigator,"connection",{value:window.__qaConnection});' });
	await call("Fetch.enable", { patterns: [
		{ urlPattern: "https://api.mapbox.com/*" }, { urlPattern: "https://events.mapbox.com/*" },
		{ urlPattern: "*/api/search" }, { urlPattern: "*/app/v1/public/map?*" },
		{ urlPattern: "*/app/v1/public/users/*/details" }, { urlPattern: "*/app/v1/public/data/users*" },
		{ urlPattern: "*/app/v1/users/username/*" }, { urlPattern: "*storage.googleapis.com/*/qa-thumbnail-*" },
	] });
	await call("Page.navigate", { url: `${base}/search` });
	await wait('!!document.querySelector("input")');
	await evaluate('document.querySelector("input").focus(); document.querySelector("input").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 1');
	assert.equal(await evaluate('!!document.activeElement.closest("[aria-hidden=true]")'), false);
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent === "Close").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 0');
	assert.equal(await evaluate('document.activeElement.tagName'), "INPUT");
	await evaluate("document.activeElement.blur()");
	for (const [key,code] of [["/","Slash"],["Escape","Escape"]]) {
		await call("Input.dispatchKeyEvent", { type: "keyDown", key, code });
		await call("Input.dispatchKeyEvent", { type: "keyUp", key, code });
		await wait(`document.querySelectorAll("[role=dialog]").length === ${key === "/" ? 1 : 0}`);
	}

	await call("Input.dispatchMouseEvent", { type: "mouseMoved", x: 5, y: 5 });
	await call("Page.navigate", { url: `${base}/map?lat=40.73&lng=-73.99&zoom=12` });
	await wait('document.querySelectorAll(".mapboxgl-marker").length === 250');
	await wait('document.querySelectorAll(".mapboxgl-marker img").length === 250 && Array.from(document.querySelectorAll(".mapboxgl-marker img")).every(img=>img.complete && img.naturalWidth > 0)');
	assert.equal(loadedImages, 250); assert.ok(maxImages <= 4, `thumbnail concurrency ${maxImages} > 4`);
	assert.equal(profileReads.length, 0); assert.equal(detailRequests.length, 0);
	await sleep(1000); assert.equal(mapRequests.length, 2, "one foreground map request + one bounded idle buffer prefetch");

	// Cached nearby pan: neither foreground data nor a redundant new idle buffer request.
	await call("Input.dispatchMouseEvent", { type: "mouseMoved", x: 50, y: 300 });
	await call("Input.dispatchMouseEvent", { type: "mousePressed", x: 50, y: 300, button: "left", clickCount: 1 });
	for (const x of [55,60,65,70]) { await call("Input.dispatchMouseEvent", { type: "mouseMoved", x, y: 300, buttons: 1 }); await sleep(80); }
	await call("Input.dispatchMouseEvent", { type: "mouseReleased", x: 70, y: 300, button: "left", clickCount: 1 });
	await sleep(1200); assert.equal(mapRequests.length, 2, "small pan reuses complete buffered data");

	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent.includes("venues")).click()');
	await wait('document.body.textContent.includes("undiscovered performers")');
	assert.equal(profileReads.length, 0, "opening area sheet must not fetch profiles");
	assert.equal(detailRequests.length, 0);
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent === "Close").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 0');

	// Hold details response to prove opening uses the cached venue rather than waiting for HTTP.
	detailDelay = 1600;
	await evaluate(`document.querySelector('button[aria-label="View Venue 0"]').focus({preventScroll:true})`);
	for (let i = 0; i < 50 && detailRequests.length === 0; i++) await sleep(20);
	assert.deepEqual(detailRequests, ["venue-0"], "keyboard intent warms one bundled details request");
	await evaluate(`document.querySelector('button[aria-label="View Venue 0"]').click()`);
	await wait('Array.from(document.querySelectorAll("h1")).some(h=>h.textContent === "Venue 0")');
	assert.deepEqual(detailRequests, ["venue-0"], "opening joins the already-running prefetch");
	await wait('Array.from(document.querySelectorAll("h1")).some(h=>h.textContent === "Fresh Venue 0")');
	await wait('document.body.textContent.includes("Cached reviewer")');
	assert.equal(profileReads.length, 0, "normalized ID/username/reviewer/top-performer caches eliminate N+1 reads");
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent === "Close").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 0');

	// A fresh authoritative 404 wins over the prefetched public snapshot.
	detailDelay = 80; deleted.add("venue-0");
	await evaluate(`document.querySelector('button[aria-label="View Venue 0"]').click()`);
	await wait('document.body.textContent.includes("Profile unavailable.")');
	await evaluate('Array.from(document.querySelectorAll("button")).find(b=>b.textContent === "Close").click()');
	await wait('document.querySelectorAll("[role=dialog]").length === 0');
	const before = detailRequests.length;
	await evaluate(`window.__qaConnection.saveData=true;document.querySelector('button[aria-label="View Venue 1"]').focus({preventScroll:true})`);
	await sleep(400); assert.equal(detailRequests.length, before, "save-data disables speculative profile reads");
	// An uncached pan during an outage retains the last good marker/sidebar snapshot.
	failMaps = true;
	await call("Input.dispatchMouseEvent", { type: "mousePressed", x: 50, y: 300, button: "left", clickCount: 1 });
	for (const x of [150,250,350,450]) { await call("Input.dispatchMouseEvent", { type: "mouseMoved", x, y: 300, buttons: 1 }); await sleep(80); }
	await call("Input.dispatchMouseEvent", { type: "mouseReleased", x: 450, y: 300, button: "left", clickCount: 1 });
	await wait('document.body.textContent.includes("Map refresh unavailable.")');
	assert.equal(await evaluate('document.querySelectorAll(".mapboxgl-marker").length'), 250);
	assert.equal(interceptionError, undefined);
	assert.equal(warnings.some((warning) => /Blocked aria-hidden|retained focus/.test(warning)), false);
	console.log("Chrome QA passed: dialog focus; one map bundle + idle buffer; cached pan/area/profile; no N+1 reads; hover dedup; fresh 404; save-data guard; outage retention; 250 thumbnails ≤4 concurrent");
} catch (error) {
	console.error({ interceptionError, warnings, mapRequests, detailRequests, profileReads, loadedImages, maxImages, page: await evaluate('({url:location.href,markers:document.querySelectorAll(".mapboxgl-marker").length,text:document.body.innerText.slice(0,300)})') });
	throw error;
} finally {
	ws.close(); await fetch(`${cdp}/json/close/${tab.id}`);
}

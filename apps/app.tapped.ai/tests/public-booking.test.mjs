import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/public-booking.ts", import.meta.url), "utf8"), {
	compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
});
const { publicBooking, publicEventUrl } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("confirmed public bookings decode dates without private fields", () => {
	const booking = publicBooking({ id: "b", status: "confirmed", startTime: "2023-11-22T20:00:00Z", name: "The party", note: "secret", rate: 100, serviceId: "private", requesterId: "r", requesteeId: "p" });
	assert.equal(booking.name, "The party");
	assert.equal(booking.startTime.toISOString(), "2023-11-22T20:00:00.000Z");
	for (const field of ["note", "rate", "serviceId"]) assert.equal(field in booking, false);
});

test("non-public bookings are unavailable; malformed legacy dates do not crash", () => {
	for (const status of ["pending", "canceled", undefined]) assert.equal(publicBooking({ id: "b", status }), null);
	assert.equal(publicBooking({ id: "b", status: "confirmed", startTime: "invalid" }).startTime, null);
});

test("event links allow only absolute http(s) URLs", () => {
	assert.equal(publicEventUrl("https://example.com/show"), "https://example.com/show");
	for (const url of [null, "javascript:alert(1)", "data:text/html,test", "/booking/b"]) assert.equal(publicEventUrl(url), null);
});

test("booking cards target an existing route backed by no-store public lookup", () => {
	const page = readFileSync(new URL("../src/app/(unauth)/booking/[bookingId]/page.tsx", import.meta.url), "utf8");
	assert.match(page, /if \(!booking\) notFound\(\)/);
	const db = readFileSync(new URL("../src/data/database.ts", import.meta.url), "utf8");
	assert.match(db, /public\/data\/bookings\/\$\{id\(bookingId\)\}[^;]+"no-store"/);
});

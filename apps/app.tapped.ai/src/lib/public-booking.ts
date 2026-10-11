export type PublicBooking = {
	id: string;
	name: string;
	requesterId: string | null;
	requesteeId: string | null;
	startTime: Date | null;
	endTime: Date | null;
	flierUrl: string | null;
	eventUrl: string | null;
};

export function publicBooking(value: Record<string, unknown>): PublicBooking | null {
	if (value.status !== "confirmed" || typeof value.id !== "string") return null;
	const date = (value: unknown) => {
		if (typeof value !== "string") return null;
		const date = new Date(value);
		return Number.isNaN(date.getTime()) ? null : date;
	};
	const text = (value: unknown) => (typeof value === "string" && value ? value : null);
	return {
		id: value.id,
		name: text(value.name) ?? "Live performance",
		requesterId: text(value.requesterId),
		requesteeId: text(value.requesteeId),
		startTime: date(value.startTime),
		endTime: date(value.endTime),
		flierUrl: text(value.flierUrl),
		eventUrl: text(value.eventUrl),
	};
}

export function publicEventUrl(value: string | null): string | null {
	if (!value) return null;
	try {
		const url = new URL(value);
		return ["https:", "http:"].includes(url.protocol) ? url.href : null;
	} catch {
		return null;
	}
}

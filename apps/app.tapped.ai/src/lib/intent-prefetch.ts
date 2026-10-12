// One speculative operation at a time, last intent wins, dwell delay avoids hover drive-bys.
export function createIntentPrefetch(
	load: (key: string) => Promise<unknown>,
	allowed: () => boolean,
	dwell = 250,
	maxPerMinute = 8
) {
	let active = false;
	let pending: { key: string; ready: boolean } | null = null;
	let timer: ReturnType<typeof setTimeout> | undefined;
	let started: number[] = [];
	const run = () => {
		if (active || !pending?.ready) return;
		const now = Date.now();
		started = started.filter((time) => now - time < 60_000);
		if (!allowed() || started.length >= maxPerMinute) {
			pending = null;
			return;
		}
		const { key } = pending;
		pending = null;
		active = true;
		started.push(now);
		Promise.resolve()
			.then(() => load(key))
			.catch(() => {})
			.finally(() => {
				active = false;
				run();
			});
	};
	return (key: string) => {
		clearTimeout(timer);
		const intent = { key, ready: false };
		pending = intent;
		if (allowed())
			timer = setTimeout(() => {
				if (pending === intent) {
					intent.ready = true;
					run();
				}
			}, dwell);
		return () => {
			if (pending === intent) {
				pending = null;
				clearTimeout(timer);
			}
		};
	};
}

export function speculativeNetworkAllowed(): boolean {
	if (typeof navigator === "undefined" || typeof document === "undefined") return false;
	const connection = (
		navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string } }
	).connection;
	return (
		document.visibilityState === "visible" &&
		!connection?.saveData &&
		!["slow-2g", "2g", "3g"].includes(connection?.effectiveType ?? "")
	);
}

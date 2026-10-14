// Track active requests across viewport changes; callers choose their CDN loading concurrency.
export function createImageQueue(concurrency = 4, retainActiveOnCancel = false) {
	if (!Number.isInteger(concurrency) || concurrency < 1)
		throw new Error("Invalid image concurrency");
	type Job = {
		start: (done: () => void) => void;
		active: boolean;
		settled: boolean;
		priority: number;
	};
	let active = 0;
	let waiting: Job[] = [];
	const finish = (job: Job) => {
		if (job.settled) return;
		job.settled = true;
		if (job.active) active--;
		else waiting = waiting.filter((pending) => pending !== job);
		drain();
	};
	const drain = () => {
		while (active < concurrency && waiting.length) {
			const job = waiting.shift();
			if (!job || job.settled) continue;
			job.active = true;
			active++;
			job.start(() => finish(job));
		}
	};
	return (start: Job["start"], priority = 0) => {
		const job: Job = { start, active: false, settled: false, priority };
		waiting.push(job);
		waiting.sort((a, b) => b.priority - a.priority);
		drain();
		return () => {
			if (!(retainActiveOnCancel && job.active)) finish(job);
		};
	};
}

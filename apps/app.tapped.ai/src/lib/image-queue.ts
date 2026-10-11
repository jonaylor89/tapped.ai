// imgproxy has two workers. Avoid sending an entire map's cold thumbnails into its timeout queue.
export function createImageQueue(concurrency = 4) {
	if (!Number.isInteger(concurrency) || concurrency < 1)
		throw new Error("Invalid image concurrency");
	type Job = { start: (done: () => void) => void; active: boolean; settled: boolean };
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
	return (start: Job["start"]) => {
		const job: Job = { start, active: false, settled: false };
		waiting.push(job);
		drain();
		return () => finish(job);
	};
}

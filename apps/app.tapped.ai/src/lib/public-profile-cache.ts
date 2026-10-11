// Public projections only. One entry per ID; username aliases share the same freshness/eviction.
export class PublicProfileCache<T extends { id: string; username: string; deleted?: boolean }> {
	private rows = new Map<string, { value: T | null; username: string | null; fetchedAt: number }>();
	private aliases = new Map<string, string>();
	constructor(
		private max = 2000,
		private freshFor = 60_000,
		private retainFor = 300_000,
		private now = Date.now
	) {}

	put(value: T, fetchedAt = this.now()): void {
		if (value.deleted) {
			this.missing(value.id, fetchedAt);
			return;
		}
		this.write(value.id, value, value.username.toLowerCase(), fetchedAt);
	}
	missing(id: string, fetchedAt = this.now()): void {
		this.write(id, null, this.rows.get(id)?.username ?? null, fetchedAt);
	}
	private write(id: string, value: T | null, username: string | null, fetchedAt: number) {
		const old = this.rows.get(id);
		if (
			old &&
			(old.fetchedAt > fetchedAt ||
				(old.fetchedAt === fetchedAt && old.value === null && value !== null))
		)
			return; // An obsolete prefetch cannot undo a newer read/404.
		this.remove(id);
		this.rows.set(id, { value, username, fetchedAt });
		if (username) this.aliases.set(username, id);
		while (this.rows.size > this.max) {
			const oldest = this.rows.keys().next().value;
			if (oldest === undefined) break;
			this.remove(oldest);
		}
	}
	private remove(id: string) {
		const old = this.rows.get(id);
		if (old?.username && this.aliases.get(old.username) === id) this.aliases.delete(old.username);
		this.rows.delete(id);
	}
	getById(id: string, allowStale = false): T | null | undefined {
		const row = this.rows.get(id);
		if (!row) return undefined;
		const age = this.now() - row.fetchedAt;
		if (age >= this.retainFor) {
			this.remove(id);
			return undefined;
		}
		if (!allowStale && age >= this.freshFor) return undefined;
		this.rows.delete(id);
		this.rows.set(id, row);
		return row.value;
	}
	getByUsername(username: string, allowStale = false): T | null | undefined {
		const id = this.aliases.get(username.toLowerCase());
		return id ? this.getById(id, allowStale) : undefined;
	}
	get size(): number {
		return this.rows.size;
	}
}

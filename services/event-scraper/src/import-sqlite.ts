/**
 * One-off: copies the state of an old SQLite file into the Postgres schema, so discovery that already cost API calls
 * is not repeated. Existing rows win. Ids are preserved, so run it on an empty schema before any new work.
 */
import { all, type Db, type Row, run, transaction } from "./db.js";

const BOOL_COLUMNS: Record<string, string[]> = { sources: ["enabled"], venue_place_ids: ["is_canonical"] };
const SEQUENCED = ["jobs", "events", "event_changes", "alerts", "venue_candidates", "publish_outbox"];
/** Parents before children. */
const TABLES = [
  "venues",
  "sources",
  "fetch_state",
  "jobs",
  "events",
  "event_changes",
  "alerts",
  "venue_candidates",
  "venue_place_ids",
  "publish_outbox",
  "kv",
  "host_slots",
];

function convert(table: string, column: string, value: unknown): string | number | boolean | null {
  if (value == null) return null;
  if (BOOL_COLUMNS[table]?.includes(column)) return Number(value) === 1;
  return value as string | number;
}

export async function importSqlite(db: Db, path: string): Promise<Record<string, number>> {
  const { DatabaseSync } = await import("node:sqlite");
  const source = new DatabaseSync(path, { readOnly: true });
  const counts: Record<string, number> = {};
  try {
    // Upload outside the transaction; registering them afterwards keeps it short.
    const pages = source.prepare("SELECT * FROM raw_pages").all() as Row[];
    const refs = new Map<string, unknown>();
    for (const page of pages) {
      refs.set(
        String(page.sha256),
        await db.pages.put(String(page.sha256), page.bytes as Uint8Array, page.content_type),
      );
    }
    await transaction(db, async () => {
      for (const table of TABLES) {
        const rows = source.prepare(`SELECT * FROM ${table}`).all() as Row[];
        let copied = 0;
        for (const row of rows) {
          const columns = Object.keys(row);
          const inserted = await run(
            db,
            `INSERT INTO ${table} (${columns.join(",")}) VALUES (${columns.map(() => "?").join(",")}) ON CONFLICT DO NOTHING`,
            ...columns.map((column) => convert(table, column, row[column])),
          );
          copied += inserted.changes;
        }
        counts[table] = copied;
      }
      let copiedPages = 0;
      for (const page of pages) {
        const inserted = await run(
          db,
          `INSERT INTO raw_pages (sha256,url,content_type,size,ref,first_seen_at) VALUES (?,?,?,?,?,?)
           ON CONFLICT DO NOTHING`,
          page.sha256,
          page.url,
          page.content_type,
          page.size,
          JSON.stringify(refs.get(String(page.sha256))),
          page.first_seen_at,
        );
        copiedPages += inserted.changes;
      }
      counts.raw_pages = copiedPages;
      for (const table of SEQUENCED) {
        await all(
          db,
          `SELECT setval(pg_get_serial_sequence('${table}','id'), GREATEST((SELECT COALESCE(MAX(id),0) FROM ${table}),1))`,
        );
      }
    });
    return counts;
  } finally {
    source.close();
  }
}

/**
 * Where raw page bytes live. Postgres only keeps a pointer (`raw_pages.ref`): the server is small and evidence pages
 * would bloat it. With SCRAPE_R2_* configured, pages go to the private scrape bucket, readable from every laptop;
 * without it they stay on this laptop's disk, which is only good for dry runs.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { gunzip } from "node:zlib";

const decompress = promisify(gunzip);

export type PageRef = Record<string, unknown>;

export interface PageStore {
  put(sha256: string, bytes: Uint8Array, contentType: string | null): Promise<PageRef>;
  get(ref: PageRef): Promise<Uint8Array>;
}

/** For tests. */
export class MemoryPageStore implements PageStore {
  private readonly pages = new Map<string, Uint8Array>();

  async put(sha256: string, bytes: Uint8Array): Promise<PageRef> {
    this.pages.set(sha256, bytes);
    return { store: "memory", sha256 };
  }

  async get(ref: PageRef): Promise<Uint8Array> {
    const bytes = this.pages.get(String(ref.sha256));
    if (!bytes) throw new Error("Raw page is not in this memory store");
    return bytes;
  }
}

export class DiskPageStore implements PageStore {
  private readonly dir: string;

  constructor(dir: string) {
    this.dir = resolve(dir);
  }

  async put(sha256: string, bytes: Uint8Array): Promise<PageRef> {
    mkdirSync(this.dir, { recursive: true });
    writeFileSync(join(this.dir, sha256), bytes);
    return { store: "disk", sha256 };
  }

  async get(ref: PageRef): Promise<Uint8Array> {
    if (ref.store !== "disk" || !/^[a-f0-9]{64}$/.test(String(ref.sha256))) throw new Error("Not a page on this disk");
    return readFileSync(join(this.dir, String(ref.sha256)));
  }
}

/** The private scrape bucket, through the same content-addressed store published evidence uses. */
export class R2PageStore implements PageStore {
  private store: Promise<import("@tapped/postgres-ingestion").S3EvidenceStore> | null = null;

  constructor(private readonly env: NodeJS.ProcessEnv = process.env) {}

  private evidence() {
    this.store ??= import("@tapped/postgres-ingestion").then((m) => m.r2EvidenceStore(this.env));
    return this.store;
  }

  async put(_sha256: string, bytes: Uint8Array, contentType: string | null): Promise<PageRef> {
    const store = await this.evidence();
    const ref = await store.put(Buffer.from(bytes), {
      retention: "evidence",
      contentType: contentType ?? "application/octet-stream",
    });
    return { store: "r2", ...ref };
  }

  async get(ref: PageRef): Promise<Uint8Array> {
    if (ref.store !== "r2") throw new Error("Not a page in R2; it was stored on another laptop's disk");
    const store = await this.evidence();
    const url = await store.downloadUrl(ref as unknown as Parameters<typeof store.downloadUrl>[0]);
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Raw page download failed: ${response.status}`);
    return decompress(Buffer.from(await response.arrayBuffer()));
  }
}

export function pageStoreFromEnv(env: NodeJS.ProcessEnv, dataDir: string): PageStore {
  return env.SCRAPE_R2_BUCKET?.trim() ? new R2PageStore(env) : new DiskPageStore(join(dataDir, "pages"));
}

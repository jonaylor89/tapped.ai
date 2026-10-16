import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { gzipSync } from "node:zlib";
import { R2ArchiveReader } from "../src/r2-archive-reader";

const env = {
  SCRAPE_R2_ACCOUNT_ID: "a".repeat(32),
  SCRAPE_R2_ARCHIVE_BUCKET: "private-archive",
  SCRAPE_R2_ARCHIVE_ACCESS_KEY_ID: "archive-test-key",
  SCRAPE_R2_ARCHIVE_SECRET_ACCESS_KEY: "archive-test-secret",
};
const raw = Buffer.from("{}\n");
const compressed = gzipSync(raw);
const sha256 = createHash("sha256").update(compressed).digest("hex");
const ref = {
  bucket: env.SCRAPE_R2_ARCHIVE_BUCKET,
  key: `archive/${sha256.slice(0, 2)}/${sha256}.gz`,
  sha256,
  bytes: compressed.length,
  contentType: "application/x-ndjson",
  contentEncoding: "gzip" as const,
};
function client(reader: R2ArchiveReader) {
  return (
    reader as unknown as {
      client: {
        send: (command: unknown) => Promise<unknown>;
        config: { credentials: () => Promise<{ sessionToken?: string }> };
      };
    }
  ).client;
}
function response(patch: Record<string, unknown> = {}) {
  return {
    ContentLength: ref.bytes,
    ContentEncoding: "gzip",
    ContentType: ref.contentType,
    Metadata: { sha256 },
    Body: { transformToByteArray: async () => compressed },
    ...patch,
  };
}
test("read-only archive transport verifies response headers and recovered bytes", async () => {
  const reader = new R2ArchiveReader(env);
  try {
    client(reader).send = async () => response();
    assert.deepEqual(await reader.read(ref), raw);
    assert.equal(reader.fetchedObjects, 1);
    assert.equal(reader.compressedBytes, compressed.length);
    await assert.rejects(reader.read({ ...ref, bucket: "other" }), /reference/);
  } finally {
    reader.close();
  }
});
test("bad response headers close the stream before buffering; tampered bodies fail closed", async () => {
  const reader = new R2ArchiveReader(env);
  let buffered = false,
    destroyed = false;
  try {
    client(reader).send = async () =>
      response({
        ContentLength: ref.bytes + 1,
        Body: {
          transformToByteArray: async () => {
            buffered = true;
            return compressed;
          },
          destroy: () => {
            destroyed = true;
          },
        },
      });
    await assert.rejects(reader.read(ref), /metadata/);
    assert.equal(buffered, false);
    assert.equal(destroyed, true);
    const altered = Buffer.from(compressed);
    altered[altered.length - 1] ^= 1;
    client(reader).send = async () => response({ Body: { transformToByteArray: async () => altered } });
    await assert.rejects(reader.read(ref), /checksum/);
    assert.equal(reader.fetchedObjects, 0);
  } finally {
    reader.close();
  }
});
test("archive reads never fall back to runtime or media credentials", async () => {
  assert.throws(() => new R2ArchiveReader({}), /credentials/);
  assert.throws(() => new R2ArchiveReader({ ...env, SCRAPE_R2_ARCHIVE_BUCKET: "not/a/bucket" }), /credentials/);
  assert.throws(() => new R2ArchiveReader({ ...env, SCRAPE_R2_ARCHIVE_BUCKET: "tapped-media" }), /credentials/);
  assert.throws(() => new R2ArchiveReader({ ...env, SCRAPE_R2_BUCKET: env.SCRAPE_R2_ARCHIVE_BUCKET }), /credentials/);
  const reader = new R2ArchiveReader({
    ...env,
    SCRAPE_R2_SESSION_TOKEN: "runtime-only",
    SCRAPE_R2_ARCHIVE_SESSION_TOKEN: "archive-only",
  });
  try {
    assert.equal((await client(reader).config.credentials()).sessionToken, "archive-only");
  } finally {
    reader.close();
  }
});

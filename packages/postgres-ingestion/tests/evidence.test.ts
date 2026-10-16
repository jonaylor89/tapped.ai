import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { gunzipSync } from "node:zlib";
import { HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { r2ArchiveStore, r2EvidenceStore, S3EvidenceStore } from "../src/evidence";

function mockClient() {
  const objects = new Map<string, PutObjectCommand["input"]>();
  let puts = 0;
  const client = {
    send: async (command: HeadObjectCommand | PutObjectCommand) => {
      const key = command.input.Key ?? "";
      if (command instanceof HeadObjectCommand) {
        const obj = objects.get(key);
        if (!obj) throw { $metadata: { httpStatusCode: 404 } };
        return {
          ContentLength: obj.ContentLength,
          Metadata: obj.Metadata,
          ContentType: obj.ContentType,
          ContentEncoding: obj.ContentEncoding,
        };
      }
      puts++;
      objects.set(key, command.input);
      return {};
    },
  } as unknown as S3Client;
  return { client, objects, puts: () => puts };
}
test("R2 captures deterministic compressed evidence, verifies it, and reuses immutable objects", async () => {
  const mock = mockClient();
  const store = new S3EvidenceStore(mock.client, "tapped-scrape-private-test");
  const raw = Buffer.from('{"raw":"html & extraction"}\n');
  const first = await store.put(raw, { retention: "archive", contentType: "application/x-ndjson" });
  const second = await store.put(raw, { retention: "archive", contentType: "application/x-ndjson" });
  assert.deepEqual(first, second);
  assert.equal(mock.puts(), 1);
  const object = mock.objects.get(first.key);
  assert.ok(object);
  const body = object.Body as Buffer;
  assert.deepEqual(gunzipSync(body), raw);
  assert.equal(first.sha256, createHash("sha256").update(body).digest("hex"));
  assert.equal(object.ContentMD5, createHash("md5").update(body).digest("base64"));
  assert.equal(object.IfNoneMatch, "*");
  assert.match(first.key, /^archive\/[a-f0-9]{2}\/[a-f0-9]{64}\.gz$/);
  object.Metadata = { sha256: "wrong" };
  await assert.rejects(store.put(raw, { retention: "archive", contentType: "application/x-ndjson" }), /verification/);
});
test("a concurrent conditional upload is verified, rather than overwritten", async () => {
  const mock = mockClient();
  const original = mock.client.send.bind(mock.client);
  mock.client.send = (async (command: HeadObjectCommand | PutObjectCommand) => {
    const result = await original(command);
    if (command instanceof PutObjectCommand) throw { $metadata: { httpStatusCode: 412 } };
    return result;
  }) as S3Client["send"];
  await new S3EvidenceStore(mock.client, "tapped-scrape-private-test").put(Buffer.from("raw"), {
    retention: "evidence",
    contentType: "text/html",
  });
  assert.equal(mock.puts(), 1);
});
test("storage fails closed and never uses media credentials or public buckets", () => {
  assert.throws(() =>
    r2EvidenceStore({ R2_ACCOUNT_ID: "a".repeat(32), R2_ACCESS_KEY_ID: "key", R2_SECRET_ACCESS_KEY: "secret" }),
  );
  assert.throws(() => new S3EvidenceStore(mockClient().client, "tapped-media"));
  assert.throws(() => new S3EvidenceStore(mockClient().client, "tapped-media-archive"));
  const runtime = {
    SCRAPE_R2_ACCOUNT_ID: "a".repeat(32),
    SCRAPE_R2_ACCESS_KEY_ID: "key",
    SCRAPE_R2_SECRET_ACCESS_KEY: "secret",
    SCRAPE_R2_BUCKET: "runtime-only",
  };
  assert.throws(() => r2ArchiveStore(runtime));
  assert.throws(() => r2ArchiveStore({ ...runtime, SCRAPE_R2_ARCHIVE_BUCKET: "runtime-only" }));
});
test("diagnostic links expire quickly and force attachment download", async () => {
  const client = new S3Client({
    region: "auto",
    endpoint: `https://${"a".repeat(32)}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId: "test", secretAccessKey: "test" },
  });
  const store = new S3EvidenceStore(client, "tapped-scrape-private-test");
  const ref = {
    bucket: "tapped-scrape-private-test",
    key: `evidence/aa/${"a".repeat(64)}.gz`,
    sha256: "a".repeat(64),
    bytes: 100,
    contentType: "text/html",
    contentEncoding: "gzip" as const,
  };
  const url = new URL(await store.downloadUrl(ref));
  assert.equal(url.searchParams.get("X-Amz-Expires"), "60");
  assert.match(url.searchParams.get("response-content-disposition") ?? "", /^attachment/);
  assert.equal(url.searchParams.get("response-content-encoding"), "identity");
  assert.equal(url.searchParams.get("response-cache-control"), "private, no-store");
  await assert.rejects(store.downloadUrl(ref, 3600));
  await assert.rejects(store.downloadUrl({ ...ref, bucket: "other" }));
  client.destroy();
});
test("temporary credentials keep runtime and archive session tokens isolated", async () => {
  const env = {
    SCRAPE_R2_ACCOUNT_ID: "a".repeat(32),
    SCRAPE_R2_BUCKET: "runtime-only",
    SCRAPE_R2_ACCESS_KEY_ID: "key",
    SCRAPE_R2_SECRET_ACCESS_KEY: "runtime-secret",
    SCRAPE_R2_SESSION_TOKEN: "runtime-session",
    SCRAPE_R2_ARCHIVE_BUCKET: "archive-only",
    SCRAPE_R2_ARCHIVE_ACCESS_KEY_ID: "key",
    SCRAPE_R2_ARCHIVE_SECRET_ACCESS_KEY: "archive-secret",
    SCRAPE_R2_ARCHIVE_SESSION_TOKEN: "archive-session",
  };
  const reference = {
    bucket: "runtime-only",
    key: `evidence/aa/${"a".repeat(64)}.gz`,
    sha256: "a".repeat(64),
    bytes: 100,
    contentType: "application/json",
    contentEncoding: "gzip" as const,
  };
  const runtime = new URL(await r2EvidenceStore(env).downloadUrl(reference));
  const archive = new URL(
    await r2ArchiveStore(env).downloadUrl({
      ...reference,
      bucket: "archive-only",
      key: reference.key.replace("evidence/", "archive/"),
    }),
  );
  assert.equal(runtime.searchParams.get("X-Amz-Security-Token"), "runtime-session");
  assert.equal(archive.searchParams.get("X-Amz-Security-Token"), "archive-session");
});

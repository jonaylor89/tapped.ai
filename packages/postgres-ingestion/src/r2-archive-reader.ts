import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import type { EvidenceRef } from "./evidence";
import {
  type ArchivedDocument,
  type ArchiveEntry,
  parseArchivedDocuments,
  recoverArchiveBytes,
  validateArchiveReference,
} from "./firestore-archive";

/** Read-only S3 adapter: no Firebase dependency and no object write/delete operations. */
export class R2ArchiveReader {
  private readonly client: S3Client;
  readonly bucket: string;
  fetchedObjects = 0;
  compressedBytes = 0;
  constructor(env: NodeJS.ProcessEnv = process.env) {
    const account = env.SCRAPE_R2_ACCOUNT_ID;
    const bucket = env.SCRAPE_R2_ARCHIVE_BUCKET;
    const accessKeyId = env.SCRAPE_R2_ARCHIVE_ACCESS_KEY_ID;
    const secretAccessKey = env.SCRAPE_R2_ARCHIVE_SECRET_ACCESS_KEY;
    if (
      !account ||
      !/^[a-f0-9]{32}$/.test(account) ||
      !bucket ||
      !/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(bucket) ||
      !accessKeyId ||
      !secretAccessKey ||
      ["tapped-media", "tapped-media-archive", env.SCRAPE_R2_BUCKET].includes(bucket)
    )
      throw new Error("Dedicated private archive credentials are required");
    this.bucket = bucket;
    this.client = new S3Client({
      region: "auto",
      forcePathStyle: true,
      endpoint: `https://${account}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId, secretAccessKey, sessionToken: env.SCRAPE_R2_ARCHIVE_SESSION_TOKEN || undefined },
      requestChecksumCalculation: "WHEN_REQUIRED",
      responseChecksumValidation: "WHEN_REQUIRED",
      maxAttempts: 3,
      requestHandler: { connectionTimeout: 10_000, requestTimeout: 60_000 },
    });
  }
  async read(reference: EvidenceRef): Promise<Buffer> {
    const ref = validateArchiveReference(reference, this.bucket);
    const response = await this.client.send(new GetObjectCommand({ Bucket: ref.bucket, Key: ref.key }));
    if (
      !response.Body ||
      response.ContentLength !== ref.bytes ||
      response.Metadata?.sha256 !== ref.sha256 ||
      response.ContentEncoding !== "gzip" ||
      response.ContentType !== ref.contentType
    ) {
      if (response.Body && "destroy" in response.Body && typeof response.Body.destroy === "function")
        response.Body.destroy();
      throw new Error("Archive response metadata mismatch");
    }
    const compressed = Buffer.from(await response.Body.transformToByteArray());
    const raw = await recoverArchiveBytes(compressed, ref);
    this.fetchedObjects++;
    this.compressedBytes += compressed.length;
    return raw;
  }
  /** Fetch bounded windows concurrently; emit in manifest order, with no unhandled pending reads. */
  async *documents(
    entries: ArchiveEntry[],
    concurrency = 4,
  ): AsyncGenerator<{ entry: ArchiveEntry; documents: ArchivedDocument[] }> {
    if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 8)
      throw new Error("Invalid archive concurrency");
    for (let i = 0; i < entries.length; i += concurrency) {
      const window = entries.slice(i, i + concurrency);
      const results = await Promise.allSettled(
        window.map(async (entry) => ({
          entry,
          documents: parseArchivedDocuments(await this.read(entry.evidence), entry),
        })),
      );
      for (const result of results) {
        if (result.status === "rejected") throw result.reason;
        yield result.value;
      }
    }
  }
  close(): void {
    this.client.destroy();
  }
}

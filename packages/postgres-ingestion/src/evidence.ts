import { createHash } from "node:crypto";
import { promisify } from "node:util";
import { gzip } from "node:zlib";
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const compress = promisify(gzip);

export type EvidenceRef = {
  bucket: string;
  key: string;
  sha256: string;
  bytes: number;
  contentType: string;
  contentEncoding: "gzip";
};
export interface EvidenceStore {
  put(bytes: Buffer, options: { retention: "archive" | "evidence"; contentType: string }): Promise<EvidenceRef>;
}

/** Separate private bucket and credentials. Never fall back to public application media. */
export class S3EvidenceStore implements EvidenceStore {
  constructor(
    private readonly client: S3Client,
    private readonly bucket: string,
  ) {
    if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(bucket) || ["tapped-media", "tapped-media-archive"].includes(bucket))
      throw new Error("A dedicated private scraper bucket is required");
  }

  async put(raw: Buffer, options: { retention: "archive" | "evidence"; contentType: string }): Promise<EvidenceRef> {
    if (raw.length > 32 * 1024 * 1024) throw new Error("Evidence exceeds 32 MiB; split it into bounded objects");
    const body = await compress(raw);
    const sha256 = createHash("sha256").update(body).digest("hex");
    const ref: EvidenceRef = {
      bucket: this.bucket,
      key: `${options.retention}/${sha256.slice(0, 2)}/${sha256}.gz`,
      sha256,
      bytes: body.length,
      contentType: options.contentType,
      contentEncoding: "gzip",
    };
    const request = { Bucket: ref.bucket, Key: ref.key };
    const verify = async (): Promise<boolean> => {
      try {
        const head = await this.client.send(new HeadObjectCommand(request));
        if (
          head.ContentLength !== ref.bytes ||
          head.Metadata?.sha256 !== ref.sha256 ||
          head.ContentType !== ref.contentType ||
          head.ContentEncoding !== ref.contentEncoding
        )
          throw new Error("Evidence verification failed");
        return true;
      } catch (error) {
        if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode === 404) return false;
        throw error;
      }
    };
    if (!(await verify())) {
      try {
        await this.client.send(
          new PutObjectCommand({
            ...request,
            Body: body,
            ContentLength: body.length,
            ContentType: ref.contentType,
            ContentEncoding: ref.contentEncoding,
            // R2 validates MD5 of the transmitted bytes; ETag is not treated as a checksum.
            ContentMD5: createHash("md5").update(body).digest("base64"),
            Metadata: { sha256 },
            IfNoneMatch: "*",
          }),
        );
      } catch (error) {
        if ((error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode !== 412) throw error;
      }
      if (!(await verify())) throw new Error("Uploaded evidence is missing");
    }
    return ref;
  }

  /** Never return a public URL. Force downloads, especially for untrusted HTML. */
  async downloadUrl(ref: EvidenceRef, expiresIn = 60): Promise<string> {
    if (ref.bucket !== this.bucket || !/^(archive|evidence)\/[a-f0-9]{2}\/[a-f0-9]{64}\.gz$/.test(ref.key))
      throw new Error("Invalid evidence reference");
    if (!Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 300) throw new Error("Invalid download lifetime");
    return getSignedUrl(
      this.client,
      new GetObjectCommand({
        Bucket: ref.bucket,
        Key: ref.key,
        ResponseContentDisposition: 'attachment; filename="scrape-evidence.gz"',
        ResponseContentType: "application/octet-stream",
        ResponseContentEncoding: "identity",
        ResponseCacheControl: "private, no-store",
      }),
      { expiresIn },
    );
  }
}

export function r2EvidenceStore(env: NodeJS.ProcessEnv = process.env): S3EvidenceStore {
  return configuredStore(env, "SCRAPE_R2");
}

/** Historical snapshots contain private venue fields; workers must not receive archive credentials. */
export function r2ArchiveStore(env: NodeJS.ProcessEnv = process.env): S3EvidenceStore {
  if (env.SCRAPE_R2_ARCHIVE_BUCKET && env.SCRAPE_R2_ARCHIVE_BUCKET === env.SCRAPE_R2_BUCKET)
    throw new Error("Historical archives require a separate private bucket");
  return configuredStore(env, "SCRAPE_R2_ARCHIVE");
}

function configuredStore(env: NodeJS.ProcessEnv, prefix: "SCRAPE_R2" | "SCRAPE_R2_ARCHIVE"): S3EvidenceStore {
  const account = env.SCRAPE_R2_ACCOUNT_ID;
  const accessKeyId = env[`${prefix}_ACCESS_KEY_ID`];
  const secretAccessKey = env[`${prefix}_SECRET_ACCESS_KEY`];
  const sessionToken = env[`${prefix}_SESSION_TOKEN`] || undefined;
  const bucket = env[`${prefix}_BUCKET`];
  if (!account || !/^[a-f0-9]{32}$/.test(account) || !accessKeyId || !secretAccessKey || !bucket)
    throw new Error(`SCRAPE_R2_ACCOUNT_ID and dedicated ${prefix}_ACCESS_KEY_ID/SECRET_ACCESS_KEY/BUCKET are required`);
  return new S3EvidenceStore(
    new S3Client({
      region: "auto",
      forcePathStyle: true,
      endpoint: `https://${account}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId, secretAccessKey, sessionToken },
      maxAttempts: 3,
      requestHandler: { connectionTimeout: 10_000, requestTimeout: 60_000 },
      // R2 uses the explicit Content-MD5 above, not AWS-only automatic checksum trailers.
      requestChecksumCalculation: "WHEN_REQUIRED",
      responseChecksumValidation: "WHEN_REQUIRED",
    }),
    bucket,
  );
}

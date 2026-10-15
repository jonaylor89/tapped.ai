# /// script
# requires-python = "==3.13.*"
# dependencies = [
#     "boto3==1.40.0",
#     "google-cloud-storage==2.19.0",
# ]
# ///
"""Copy the Firebase Storage bucket to R2 and generate the Postgres URL rewrite.

Layout (public bucket `tapped-media`, served at https://media.tapped.ai):
    users/{uid}/avatar/{sha}.{ext}           users.profile_picture
    users/{uid}/press-kits/{sha}.{ext}       press kits linked from users.profile
    opportunities/{id}/flier/{sha}.{ext}     opportunities.flier_url
    events/fliers/{sha}.{ext}                bookings.flier_url (shared fliers are stored once)
Private bucket `tapped-media-archive`:
    legacy/{original key}                    objects no live row references, including the
                                             overwritten `bookings/` and `booking/` placeholders

`{sha}` is the first 32 hex digits of the SHA-256 of the bytes, so keys are immutable and served
with `Cache-Control: immutable`. Every step is resumable and re-running it after new Firebase
uploads only copies and rewrites the delta.

    uv run scripts/migrate_storage_to_r2.py copy   --refs refs.tsv --work DIR
    uv run scripts/migrate_storage_to_r2.py verify --work DIR
    uv run scripts/migrate_storage_to_r2.py sql    --refs refs.tsv --work DIR > rewrite.sql

`refs.tsv` is `table<TAB>column<TAB>row id<TAB>url` for every Firebase URL in Postgres (see
platform/R2_MIGRATION.md). R2 credentials come from R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and
R2_SECRET_ACCESS_KEY; GCS uses Application Default Credentials (read-only is enough).
"""

import argparse
import base64
import collections
import concurrent.futures
import hashlib
import json
import os
import re
import sys
import threading
import urllib.parse
from pathlib import Path

import boto3
from botocore.config import Config
from google.cloud import storage

SOURCE_BUCKET = "in-the-loop-306520.appspot.com"
PUBLIC_BUCKET = "tapped-media"
ARCHIVE_BUCKET = "tapped-media-archive"
PUBLIC_BASE = "https://media.tapped.ai"
ARCHIVE_BASE = f"r2://{ARCHIVE_BUCKET}"
# A crawler run uploaded fliers without a file name, so these hold whichever flier came last.
PLACEHOLDERS = {"bookings/", "booking/"}
LEGACY_TABLES = {"legacy_profile_archive", "legacy_invalid_records"}
URL_KEY = re.compile(r"/(?:v0/b/[^/]+/o/|" + re.escape(SOURCE_BUCKET) + r"/)(.+)")


def source_key(url: str) -> str:
    match = URL_KEY.match(urllib.parse.urlsplit(url).path)
    if not match:
        raise ValueError(f"not a Firebase Storage URL: {url}")
    return urllib.parse.unquote(match.group(1))


def read_refs(path: Path) -> list[tuple[str, str, str, str]]:
    refs = []
    for line in path.read_text().splitlines():
        table, column, row_id, url = line.split("\t", 3)
        refs.append((table, column, row_id, url))
    return refs


def sniff(data: bytes, key: str) -> tuple[str, str]:
    """(extension, content type) from the bytes; Firebase content types are often wrong (`image/`)."""
    head = data[:16]
    if head.startswith(b"\xff\xd8\xff"):
        return "jpg", "image/jpeg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png", "image/png"
    if head.startswith((b"GIF87a", b"GIF89a")):
        return "gif", "image/gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp", "image/webp"
    if head.startswith(b"%PDF"):
        return "pdf", "application/pdf"
    if head[4:8] == b"ftyp":
        brand = head[8:12]
        if brand in (b"heic", b"heix", b"mif1", b"msf1"):
            return "heic", "image/heic"
        if brand == b"avif":
            return "avif", "image/avif"
        return "mp4", "video/mp4"
    if head.startswith(b"ID3") or (len(head) > 1 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0):
        return "mp3", "audio/mpeg"
    if head.startswith(b"BM"):
        return "bmp", "image/bmp"
    if head[:4] in (b"II*\x00", b"MM\x00*"):
        return "tiff", "image/tiff"
    if head[:4] == b"\x00\x00\x01\x00":
        return "ico", "image/x-icon"
    text = data[:2048].lower()
    if b"<svg" in text and b"<html" not in text:
        return "svg", "image/svg+xml"
    # Never trust the name: crawled HTML error pages and bot walls are often called `*.jpg`.
    return "bin", "application/octet-stream"


def is_media(content_type: str) -> bool:
    """Crawled "fliers" include HTML bot walls, error pages and empty files; those are not media."""
    return content_type.startswith(("image/", "video/", "audio/")) or content_type == "application/pdf"


def targets_for(key: str, refs: set[tuple[str, str, str]], sha: str, ext: str, media: bool = True) -> list[tuple[str, str]]:
    live = {(t, c, i) for t, c, i in refs if t not in LEGACY_TABLES}
    if key in PLACEHOLDERS or not live or not media:
        return [(ARCHIVE_BUCKET, f"legacy/{key}")]
    out = set()
    for table, column, row_id in live:
        if (table, column) == ("users", "profile_picture"):
            out.add((PUBLIC_BUCKET, f"users/{row_id}/avatar/{sha}.{ext}"))
        elif (table, column) == ("users", "profile"):
            out.add((PUBLIC_BUCKET, f"users/{row_id}/press-kits/{sha}.{ext}"))
        elif (table, column) == ("opportunities", "flier_url"):
            out.add((PUBLIC_BUCKET, f"opportunities/{row_id}/flier/{sha}.{ext}"))
        elif (table, column) == ("bookings", "flier_url"):
            out.add((PUBLIC_BUCKET, f"events/fliers/{sha}.{ext}"))
        else:
            raise ValueError(f"no layout rule for {table}.{column}")
    return sorted(out)


EXT_BY_TYPE = {"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp",
               "application/pdf": "pdf", "image/heic": "heic", "image/avif": "avif", "video/mp4": "mp4",
               "audio/mpeg": "mp3"}


def needs_copy(blob, entry: dict | None, refs: set[tuple[str, str, str]]) -> bool:
    """New or changed bytes, or the rows referencing it changed (e.g. an upload the refs export now sees)."""
    if entry is None or entry["md5"] != blob.md5_hash:
        return True
    ext = entry.get("ext") or EXT_BY_TYPE.get(entry["content_type"])
    if ext is None:
        return any(t not in LEGACY_TABLES for t, _, _ in refs)
    current = {(t["bucket"], t["key"]) for t in entry["targets"]}
    media = is_media(entry["content_type"]) and entry["size"] > 0
    return set(targets_for(blob.name, refs, entry["sha"], ext, media)) != current


def targets_are_public(targets: list[tuple[str, str]]) -> bool:
    return any(bucket == PUBLIC_BUCKET for bucket, _ in targets)


def r2_client():
    account = os.environ["R2_ACCOUNT_ID"]
    return boto3.client(
        "s3",
        endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
        config=Config(retries={"max_attempts": 8, "mode": "adaptive"}, max_pool_connections=64),
    )


def load_manifest(work: Path) -> dict[str, dict]:
    path = work / "manifest.jsonl"
    if not path.exists():
        return {}
    entries = {}
    for line in path.read_text().splitlines():
        entry = json.loads(line)
        entries[entry["source"]] = entry
    return entries


def refs_by_key(refs: list[tuple[str, str, str, str]]) -> dict[str, set[tuple[str, str, str]]]:
    by_key = collections.defaultdict(set)
    for table, column, row_id, url in refs:
        by_key[source_key(url)].add((table, column, row_id))
    return by_key


def copy(args) -> None:
    work = Path(args.work)
    work.mkdir(parents=True, exist_ok=True)
    os.chmod(work, 0o700)
    by_key = refs_by_key(read_refs(Path(args.refs)))
    done = load_manifest(work)
    gcs = storage.Client(project="in-the-loop-306520")
    recheck = set(Path(args.recheck).read_text().splitlines()) if args.recheck else set()
    blobs = [b for b in gcs.list_blobs(SOURCE_BUCKET, prefix=args.prefix)
             if b.name in recheck or needs_copy(b, done.get(b.name), by_key.get(b.name, set()))]
    print(f"{len(done)} already copied, {len(blobs)} to copy", file=sys.stderr)
    r2 = r2_client()
    lock = threading.Lock()
    manifest = open(work / "manifest.jsonl", "a")
    failures = []

    def one(blob) -> None:
        data = blob.download_as_bytes(checksum="md5")
        sha = hashlib.sha256(data).hexdigest()[:32]
        ext, content_type = sniff(data, blob.name)
        targets = targets_for(blob.name, by_key.get(blob.name, set()), sha, ext, is_media(content_type) and len(data) > 0)
        md5 = base64.b64encode(hashlib.md5(data).digest()).decode()
        for bucket, key in targets:
            r2.put_object(
                Bucket=bucket,
                Key=key,
                Body=data,
                ContentMD5=md5,
                ContentType=content_type,
                CacheControl="public, max-age=31536000, immutable" if bucket == PUBLIC_BUCKET else "private",
                Metadata={"source-key": urllib.parse.quote(blob.name, safe="/")},
            )
        # Archive keys are unique to their source, so a superseded one can go. Public keys are content
        # addressed and may be shared, so only drop one when its bytes are not media (every source
        # sharing it is moving to the archive too).
        previous = done.get(blob.name, {}).get("targets", [])
        for stale in previous:
            removable = stale["bucket"] == ARCHIVE_BUCKET or not targets_are_public(targets)
            if removable and (stale["bucket"], stale["key"]) not in targets:
                r2.delete_object(Bucket=stale["bucket"], Key=stale["key"])
        entry = {"source": blob.name, "md5": blob.md5_hash, "size": len(data), "sha": sha, "ext": ext,
                 "content_type": content_type, "targets": [{"bucket": b, "key": k} for b, k in targets]}
        with lock:
            manifest.write(json.dumps(entry) + "\n")
            manifest.flush()

    with concurrent.futures.ThreadPoolExecutor(args.concurrency) as pool:
        futures = {pool.submit(one, blob): blob.name for blob in blobs}
        for n, future in enumerate(concurrent.futures.as_completed(futures), 1):
            if error := future.exception():
                failures.append(futures[future])
                print(f"FAILED {futures[future]!r}: {error}", file=sys.stderr)
            if n % 1000 == 0:
                print(f"{n}/{len(blobs)}", file=sys.stderr)
    manifest.close()
    if failures:
        sys.exit(f"{len(failures)} objects failed; re-run to retry them")


def verify(args) -> None:
    work = Path(args.work)
    entries = load_manifest(work)
    gcs = storage.Client(project="in-the-loop-306520")
    source = {b.name: b.md5_hash for b in gcs.list_blobs(SOURCE_BUCKET, prefix=args.prefix)}
    problems = [f"not copied: {k!r}" for k in source if k not in entries]
    problems += [f"changed since copy: {k!r}" for k, md5 in source.items() if k in entries and entries[k]["md5"] != md5]
    r2 = r2_client()
    listed: dict[tuple[str, str], tuple[int, str]] = {}
    for bucket in (PUBLIC_BUCKET, ARCHIVE_BUCKET):
        for page in r2.get_paginator("list_objects_v2").paginate(Bucket=bucket):
            for obj in page.get("Contents", []):
                listed[(bucket, obj["Key"])] = (obj["Size"], obj["ETag"].strip('"'))
    expected = set()
    for entry in entries.values():
        md5_hex = base64.b64decode(entry["md5"]).hex()
        for target in entry["targets"]:
            where = (target["bucket"], target["key"])
            expected.add(where)
            got = listed.get(where)
            if got is None:
                problems.append(f"missing in R2: {where}")
            elif got != (entry["size"], md5_hex):
                problems.append(f"size/md5 mismatch: {where} {got} != {(entry['size'], md5_hex)}")
    unexpected = set(listed) - expected
    print(f"GCS objects {len(source)}, copied {len(entries)}, R2 objects {len(listed)} "
          f"(public {sum(b == PUBLIC_BUCKET for b, _ in listed)}, archive {sum(b == ARCHIVE_BUCKET for b, _ in listed)}), "
          f"unexpected R2 objects {len(unexpected)}")
    for problem in problems[:50]:
        print(problem)
    if problems or unexpected:
        sys.exit(f"{len(problems)} problems, {len(unexpected)} unexpected R2 objects")
    print("OK")


def sql_literal(value: str | None) -> str:
    return "\\N" if value is None else value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def sql(args) -> None:
    entries = load_manifest(Path(args.work))
    rows = []
    for table, column, row_id, url in read_refs(Path(args.refs)):
        key = source_key(url)
        entry = entries.get(key)
        if entry is None:
            sys.exit(f"{table}.{column} {row_id} references {key!r}, which was not copied; run copy first")
        targets = [(t["bucket"], t["key"]) for t in entry["targets"]]
        if key in PLACEHOLDERS or not (is_media(entry["content_type"]) and entry["size"] > 0):
            reason = "overwritten-placeholder" if key in PLACEHOLDERS else "not-media"
            new = None if table not in LEGACY_TABLES else f"{ARCHIVE_BASE}/legacy/{key}"
        elif targets[0][0] == ARCHIVE_BUCKET:
            reason, new = "archived", f"{ARCHIVE_BASE}/{targets[0][1]}"
        else:
            owner = {
                ("users", "profile_picture"): f"users/{row_id}/avatar/",
                ("users", "profile"): f"users/{row_id}/press-kits/",
                ("opportunities", "flier_url"): f"opportunities/{row_id}/flier/",
                ("bookings", "flier_url"): "events/fliers/",
            }.get((table, column))
            match = [k for _, k in targets if owner and k.startswith(owner)] or [targets[0][1]]
            reason, new = "moved", f"{PUBLIC_BASE}/{urllib.parse.quote(match[0])}"
        rows.append((table, column, row_id, url, new, reason))

    out = sys.stdout
    out.write("BEGIN;\n")
    out.write("CREATE TABLE IF NOT EXISTS storage_migration_map (\n"
              "    table_name text NOT NULL, column_name text NOT NULL, row_id text NOT NULL,\n"
              "    old_url text NOT NULL, new_url text, reason text NOT NULL,\n"
              "    migrated_at timestamptz NOT NULL DEFAULT now(),\n"
              "    PRIMARY KEY (table_name, column_name, row_id, old_url));\n")
    out.write("CREATE TEMP TABLE m (LIKE storage_migration_map INCLUDING DEFAULTS) ON COMMIT DROP;\n")
    out.write("COPY m (table_name, column_name, row_id, old_url, new_url, reason) FROM STDIN;\n")
    seen = set()
    for row in rows:
        if row[:4] in seen:
            continue
        seen.add(row[:4])
        out.write("\t".join(sql_literal(v) for v in row) + "\n")
    out.write("\\.\n")
    # Only rows still holding the old URL change, so re-running after a delta copy is safe.
    out.write("""
UPDATE bookings t SET flier_url = m.new_url FROM m
 WHERE m.table_name = 'bookings' AND m.column_name = 'flier_url' AND t.id::text = m.row_id AND t.flier_url = m.old_url;
UPDATE opportunities t SET flier_url = m.new_url FROM m
 WHERE m.table_name = 'opportunities' AND m.column_name = 'flier_url' AND t.id::text = m.row_id AND t.flier_url = m.old_url;
UPDATE users t SET profile_picture = m.new_url FROM m
 WHERE m.table_name = 'users' AND m.column_name = 'profile_picture' AND t.id::text = m.row_id AND t.profile_picture = m.old_url;
-- JSON documents: new URLs contain nothing JSON escapes, so a textual replace keeps them valid. A
-- NULL new URL replaces the whole JSON string with JSON null (replace() itself would return NULL).
CREATE FUNCTION pg_temp.swap_url(doc jsonb, old_url text, new_url text) RETURNS jsonb LANGUAGE sql AS $f$
  SELECT CASE WHEN new_url IS NULL
    THEN replace(doc::text, to_jsonb(old_url)::text, 'null')::jsonb
    ELSE replace(doc::text, old_url, new_url)::jsonb END
$f$;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT old_url, new_url FROM m WHERE table_name = 'users' AND column_name = 'profile' LOOP
    UPDATE users SET profile = pg_temp.swap_url(profile, r.old_url, r.new_url)
     WHERE strpos(profile::text, r.old_url) > 0;
  END LOOP;
  FOR r IN SELECT DISTINCT old_url, new_url FROM m WHERE table_name = 'legacy_profile_archive' LOOP
    UPDATE legacy_profile_archive SET profile = pg_temp.swap_url(profile, r.old_url, r.new_url)
     WHERE strpos(profile::text, r.old_url) > 0;
  END LOOP;
  FOR r IN SELECT DISTINCT old_url, new_url FROM m WHERE table_name = 'legacy_invalid_records' LOOP
    UPDATE legacy_invalid_records SET original_record = pg_temp.swap_url(original_record, r.old_url, r.new_url)
     WHERE strpos(original_record::text, r.old_url) > 0;
  END LOOP;
END $$;
INSERT INTO storage_migration_map (table_name, column_name, row_id, old_url, new_url, reason)
SELECT table_name, column_name, row_id, old_url, new_url, reason FROM m
ON CONFLICT DO NOTHING;
-- Must be zero before COMMIT.
SELECT 'remaining firebase refs' AS check,
  (SELECT count(*) FROM bookings WHERE flier_url ~ 'appspot\\.com|firebasestorage')
+ (SELECT count(*) FROM opportunities WHERE flier_url ~ 'appspot\\.com|firebasestorage')
+ (SELECT count(*) FROM users WHERE profile_picture ~ 'appspot\\.com|firebasestorage' OR profile::text ~ 'appspot\\.com|firebasestorage')
+ (SELECT count(*) FROM legacy_profile_archive WHERE profile::text ~ 'appspot\\.com|firebasestorage')
+ (SELECT count(*) FROM legacy_invalid_records WHERE original_record::text ~ 'appspot\\.com|firebasestorage') AS n;
""")
    counts = collections.Counter((r[0], r[5]) for r in rows)
    for (table, reason), n in sorted(counts.items()):
        print(f"-- {table}: {n} {reason}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("copy")
    p.add_argument("--refs", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--concurrency", type=int, default=24)
    p.add_argument("--prefix", help="only this source prefix (smoke tests)")
    p.add_argument("--recheck", help="file of source keys to re-download and re-classify")
    p = sub.add_parser("verify")
    p.add_argument("--work", required=True)
    p.add_argument("--prefix", help="only this source prefix (smoke tests)")
    p = sub.add_parser("sql")
    p.add_argument("--refs", required=True)
    p.add_argument("--work", required=True)
    args = parser.parse_args()
    {"copy": copy, "verify": verify, "sql": sql}[args.command](args)


if __name__ == "__main__":
    main()

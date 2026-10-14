# Firebase Storage → Cloudflare R2

User media moves from the Firebase bucket `in-the-loop-306520.appspot.com` to R2 in the **Tapped**
Cloudflare account. Started 2026-10-14.

| Bucket | Access | Contents |
| --- | --- | --- |
| `tapped-media` | Public at `https://media.tapped.ai`; CORS `GET`/`HEAD`/`PUT` from `tapped.ai`, `app.tapped.ai` | Everything a live row references |
| `tapped-media-archive` | Private | `legacy/{original key}`: objects no live row references |

## Layout

```
users/{uid}/avatar/{sha}.{ext}             users.profile_picture
users/{uid}/press-kits/{sha}.{ext}         press kits linked from users.profile
opportunities/{id}/flier/{sha}.{ext}       opportunities.flier_url
events/fliers/{sha}.{ext}                  bookings.flier_url (crawled fliers are shared, stored once)
```

`{sha}` is the first 32 hex digits of the SHA-256 of the bytes and `{ext}` comes from sniffing them,
because Firebase content types are often wrong. Keys never change, so objects carry
`Cache-Control: public, max-age=31536000, immutable`. Ownership is a prefix, so deleting an account's
media is one `users/{uid}/` delete.

`bookings/` and `booking/` were single objects that a crawler bug (`convertToSignedUrl` naming files
with `url.split("/").pop()`) overwrote with every flier whose URL ended in `/`; 2,712 bookings showed
whichever flier came last. They are archived and those bookings' `flier_url` is set to NULL.

## Uploads

Clients call `POST /app/v1/uploads` (`services/api.tapped.ai/src/domain/uploads.rs`) with the kind,
content type, SHA-256 and size, then `PUT` the bytes to the presigned URL and save the returned public
URL. The signature covers `content-type`, `content-length` and `x-amz-content-sha256`, so R2 rejects any
other bytes (`XAmzContentSHA256Mismatch`). The API needs `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and
`R2_SECRET_ACCESS_KEY` for a token limited to Object Read & Write on `tapped-media`; without them the
endpoint answers 503.

Cloudflare caches 404s on `media.tapped.ai`, so never hand out a URL before its `PUT` succeeded.

## Runbook

The copy runs from a workstation with `gcloud auth application-default login` and an R2 token
(Object Read & Write on both buckets) in `~/.config/tapped/r2.env`. The work directory
(`~/.local/share/tapped/r2-migration`) holds `manifest.jsonl`, the record of where every object went.
Keep it until the Firebase bucket is gone.

```sh
W=~/.local/share/tapped/r2-migration
set -a; . ~/.config/tapped/r2.env; set +a

# 1. Every Firebase URL in Postgres (read-only), as table/column/row id/url.
tailscale ssh root@tapped-prod 'cd /opt/tapped && docker compose exec -T postgres psql -U tapped -d tapped -q' \
  < platform/r2-migration/refs.sql > $W/refs.tsv

# 2. Copy (resumable; re-runs only copy new or changed objects), then verify size + MD5 of every target.
uv run scripts/migrate_storage_to_r2.py copy   --refs $W/refs.tsv --work $W
uv run scripts/migrate_storage_to_r2.py verify --work $W

# 3. Rewrite Postgres. Back up first; the script ends with a check that must report 0 before COMMIT.
tailscale ssh root@tapped-prod 'cd /opt/tapped && docker compose exec -T postgres pg_dump -U tapped -d tapped -Fc \
  -t users -t bookings -t opportunities -t legacy_profile_archive -t legacy_invalid_records' \
  > $W/pre-rewrite-$(date +%Y%m%d%H%M).dump
uv run scripts/migrate_storage_to_r2.py sql --refs $W/refs.tsv --work $W > $W/rewrite.sql
```

`rewrite.sql` opens a transaction and leaves it open; run it in an interactive `psql`, read the check
and `COMMIT` (or `ROLLBACK`). Every change is recorded in `storage_migration_map` (old URL, new URL,
reason: `moved`, `archived` or `overwritten-placeholder`); to undo, set each column back to
`old_url` from that table.

Until every client ships the R2 upload path, older App Store builds keep uploading to Firebase. Repeat
steps 1–3 to move those uploads; each run only copies and rewrites the delta.

## Retiring Firebase Storage

Deletion is irreversible and needs the owner's explicit go-ahead. Before asking:

1. The native release with `TappedAPIStorageRepository` is live and older builds are past the
   minimum supported version (Remote Config `minimumAppVersion`).
2. A final refs export finds no Firebase URLs in Postgres, and `verify` passes.
3. Request logs show traffic to `firebasestorage.googleapis.com` / `storage.googleapis.com` for the
   bucket has dropped to nothing.

Then delete the bucket's objects, remove the Firebase prefixes from `IMGPROXY_ALLOWED_SOURCES`,
`apps/app.tapped.ai/src/lib/image-loader.ts` and `ImageProxy.swift`, and delete the migration R2
token.

# Media storage (Cloudflare R2)

User media lives in R2 in the **Tapped** Cloudflare account. Firebase is used only for Auth.

| Bucket | Access | Contents |
| --- | --- | --- |
| `tapped-media` | Public at `https://media.tapped.ai`; CORS `GET`/`HEAD`/`PUT` from `tapped.ai`, `app.tapped.ai` | Everything Postgres links to |
| `tapped-media-archive` | Private | `legacy/{original Firebase key}`: files nothing links to |

## Layout

```
users/{uid}/avatar/{sha}.{ext}             users.profile_picture
users/{uid}/press-kits/{sha}.{ext}         performerInfo.pressKitUrl in users.profile
opportunities/{id}/flier/{sha}.{ext}       opportunities.flier_url
events/fliers/{sha}.{ext}                  bookings.flier_url (crawled fliers are shared, stored once)
```

`{sha}` is the first 32 hex digits of the SHA-256 of the bytes, so keys never change and objects carry
`Cache-Control: public, max-age=31536000, immutable`. Ownership is a prefix: deleting an account's
media is one `users/{uid}/` delete.

## Uploads

Clients call `POST /app/v1/uploads` (`services/api.tapped.ai/src/domain/uploads.rs`) with the kind,
content type, SHA-256 and size, `PUT` the bytes to the returned presigned URL, then save the returned
public URL. The signature covers `content-type`, `content-length` and `x-amz-content-sha256`, so R2
rejects any other bytes (`XAmzContentSHA256Mismatch`). The API reads `R2_ACCOUNT_ID`,
`R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (a token limited to Object Read & Write on
`tapped-media`); without them the endpoint answers 503.

| `kind` | Key | Accepted `contentType` | Max |
| --- | --- | --- | --- |
| `avatar` | `users/{uid}/avatar/` | JPEG, PNG, WebP, HEIC | 15 MB |
| `opportunityFlier` | `opportunities/{id}/flier/` (caller must own an existing opportunity) | JPEG, PNG, WebP, HEIC | 15 MB |
| `pressKit` | `users/{uid}/press-kits/` | PDF, `text/plain`, JPEG, PNG, WebP, HEIC; never audio, video, PPTX, HTML or SVG | 50 MB |

Cloudflare caches 404s on `media.tapped.ai`, so never hand out a URL before its `PUT` succeeded.

## Cloudflare rules on `media.tapped.ai`

A zone Transform Rule (`http_response_headers_transform`) adds `X-Content-Type-Options: nosniff` to
all press kits and, as a backstop, `Content-Security-Policy: sandbox` to any press kit ending in
`.html` or `.svg` (uploads can't create those). PDFs are deliberately not sandboxed, because Chrome
blocks its PDF viewer in sandboxed documents.

Resizing goes through imgproxy at `img.tapped.ai`, which only accepts `https://media.tapped.ai/`
sources; see [Image resizing](README.md#image-resizing-imgtappedai).

## History

On 2026-10-15 all 57,628 Firebase Storage objects were copied to R2 (each checked by size and MD5),
Postgres URLs were rewritten in one transaction, and the Firebase bucket was deleted. Crawled
"fliers" that weren't media (HTML bot walls, error pages, empty files), a crawler-overwritten
`bookings/` placeholder, and two audio/video press kits were archived and their links set to NULL.

Every rewritten or cleared link is recorded in the `storage_migration_map` table (`table_name`,
`column_name`, `row_id`, `old_url`, `new_url`, `reason`). The Firebase originals are gone, so to restore
a cleared link, copy the file from `tapped-media-archive` (`legacy/{original key}`) into
`tapped-media` and point the row at it.

# LuluFiles integration brief

> Fourni par l'utilisateur le 2026-10-08. Description de référence de l'API LuluFiles, à utiliser à l'étape 3 (contrat d'API) et à l'étape 4 (backend). La section 11 (« What I expect from you ») ne s'applique qu'à partir de l'étape 3 du pipeline.

You are a senior software engineer. Your task is to integrate **LuluFiles** as the file storage layer of my application (web and/or mobile). Read this entire brief before writing any code. It is the authoritative description of the LuluFiles API: do not invent endpoints, fields, headers or behaviours that are not described here. When something you need is not covered, say so explicitly and propose a solution on my side instead of guessing.

---

## 1. What LuluFiles is

LuluFiles is a file storage service exposed as an HTTP API. Its distinctive design:

- **File bytes live in a Telegram channel**, not on LuluFiles servers. LuluFiles uploads files to Telegram through a Telegram bot, and keeps only metadata in its own database (file name, size, MIME type, SHA-256 checksum, Telegram message references).
- **Large files are split into chunks** (about 18 MB each) sent as separate Telegram messages, then reassembled on download. This is transparent: you upload and download one file, never chunks.
- **Integrity is verified**: every chunk has a SHA-256 checksum checked before being streamed back. A corrupted chunk is detected, never silently served.
- **Deduplication**: uploading content identical (same SHA-256) to a file already stored in the same LuluFiles disk does not re-send any byte to Telegram. The new file record reuses the existing chunks and is immediately `ready`.
- **Transfers go through LuluFiles servers**: every uploaded byte transits through LuluFiles to Telegram, and every downloaded byte transits from Telegram through LuluFiles to the client. This is why quotas are based on **monthly transfer volume and bandwidth**, not on stored volume.
- **Ownership**: when you use your own Telegram channel, the files stay in that channel even if LuluFiles disappears. You would lose the index (metadata), not the content.
- **It is a file system**, not a flat bucket: an account has **disks**, a disk holds **folders**, folders hold folders and files, deleted items go to a **trash** for 30 days. If your product only needs a flat store, ignore folders: every file then lives at the root of the key's disk, exactly as before.

Base URL of the API:

```
https://lulufiles-api.onrender.com
```

Machine-readable specification (public surface only): `https://lulufiles-api.onrender.com/openapi.json`. Interactive explorer: `https://lulufiles-api.onrender.com/swagger`.

---

## 2. Core concepts

| Concept | Meaning |
|---|---|
| **Account** | A LuluFiles user account. In an integration, it is **my** account (the integrator), not the account of my end users. All quotas apply to this account as a whole. |
| **API key** | Secret of the form `lf_live_<43 chars>`, created from the LuluFiles dashboard, shown only once. Sent in the `X-API-Key` header. **A key is bound to exactly one disk** (see below). It cannot create other keys or disks, pay, share files, or reach administration. |
| **Disk** | A Telegram destination: a channel (or group, or private chat) plus an optional dedicated bot token. Every file belongs to exactly one disk. An account gets **Disque 0** on sign-up and can create more (e.g. one per environment or per product). Two disks are two channels: moving a file between them re-transfers its bytes. |
| **Application** (`app`) | The former name of a disk. The routes `/apps` and the query parameter `app_id` are still served and **deprecated**. Use `/disks` and `folder_id` in new code. |
| **Folder** | A named container inside a disk, holding folders and files. `folder_id: null` means the root of the disk. Maximum depth: 32. |
| **Key disk** | The disk a key is bound to, chosen when the key is created and **frozen** afterwards. Everything the key uploads lands there, and the key sees nothing of the account's other disks. To target another disk, revoke the key and issue a new one. |
| **Preferred disk** | What a key is bound to when no disk is given at creation: the disk flagged as default, or Disque 0 when none is. |
| **LuluFiles channel** | The shared channel behind Disque 0, used when the account has no channel of its own. Available only if `GET /config` returns `"default_channel_available": true`. |
| **File** | A logical file, in one disk and (optionally) one folder. Identified by a UUID `id`. Has a `status`: `queued` → `uploading` → `ready`, or `failed`. |
| **Trash** | Deleting puts an item in the trash: it leaves listings, keeps its bytes in Telegram, and stays restorable for **30 days** before a scheduled purge removes it for good. `?permanent=true` skips the trash. |
| **Signed link** | A temporary URL to a file's content that works **without any authentication header**, suitable for `<img>`, `<video>`, `<audio>`, `<a href>`, mobile media players and download managers. |

---

## 3. Mandatory architecture for web and mobile apps

Follow these rules. They are not optional.

1. **Never ship the API key to a client.** No API key in a browser bundle, a mobile binary, a public repository or client-side environment variables. A key embedded in an app can be extracted in minutes and gives full access to every file of the account.
2. **Put a backend between your clients and LuluFiles** (your own API, a serverless function, a BFF). Only this backend holds the key, in a server-side secret (for example `LULUFILES_API_KEY`), together with `LULUFILES_BASE_URL`. `LULUFILES_FOLDER_ID` is optional: set it to store everything in one folder of the key's disk, leave it empty to store at the disk root. Any folder outside the key's disk is rejected.
   One key per disk: if the product stores in several disks (for example one per environment), issue one key per disk and pick the right one in your code.
3. **Uploads are proxied through your backend.** LuluFiles has no pre-signed upload URL. The client sends the file to your backend, your backend authenticates and authorizes the end user, then streams the file to `POST /files/upload`. Stream the body (or spool it to a temporary file) instead of loading large files into memory.
4. **Downloads go directly from LuluFiles to the client** using signed links. Your backend checks that the end user may access the file, calls `POST /files/{id}/link`, and returns the absolute URL (`https://lulufiles-api.onrender.com` + `url`) to the client. The bytes then flow from LuluFiles to the client without passing through your backend.
5. **Keep your own ownership model.** LuluFiles does not know your end users. Store in your database, for each file: the LuluFiles `file_id`, the folder id if you use folders, the owner (your user id), the original name, size, MIME type, status, and any business metadata. Every access check happens in your backend before calling LuluFiles.
   If you mirror a folder tree for your users, keep **your own tree** as the source of truth and mirror it into LuluFiles folders; never derive a user's permissions from the LuluFiles hierarchy.
6. **Enforce per-user limits yourself.** The LuluFiles monthly transfer quota and bandwidth are shared by all your end users, because they all use your single account. Without per-user limits on your side, one heavy user can exhaust the quota for everyone.
7. **Do not call the LuluFiles API from browser JavaScript of another origin.** CORS only allows the LuluFiles web interface. Using a signed link as the `src` of a media element or as a navigation/download target works; programmatic `fetch` from your web origin does not.

Typical flows:

```
UPLOAD    client ──multipart──▶ your backend ──(X-API-Key, stream)──▶ LuluFiles ──▶ Telegram
                                     │
                                     └── store file_id + owner in your DB, return your own file DTO

STATUS    client ──▶ your backend ──▶ GET /files/{id}   (until ready or failed)

DOWNLOAD  client ──▶ your backend ──▶ POST /files/{id}/link ──▶ signed URL
          client ─────────────────── GET signed URL ─────────────────▶ LuluFiles (streams bytes, supports Range)
```

---

## 4. Authentication

Every call except `/health`, `/config` and `/plans` requires:

```
X-API-Key: lf_live_...
```

- Invalid, expired or revoked key → `401`.
- Operations reserved to a logged-in human in the LuluFiles dashboard also return `401` when called with a key: creating or revoking keys, sharing (by link or by email), reading a share received by the account, subscriptions, deleting a disk, changing a disk's bot or channel.
- Use one key per integration or environment, so each can be revoked independently.
- **A key is scoped to one disk.** Uploads go there; listing, navigation, download, preview, retry, trash and delete only ever see that disk; files and folders of other disks answer `404`, as if they did not exist. Deleting a disk revokes its keys, which then answer `401`.
- **A key never acts on a share received by the account.** Shares are a dashboard matter; with a key they answer `401`.

---

## 5. Error format

All errors share one JSON shape:

```json
{
  "error": {
    "code": "rate_limited",
    "message": "Human readable message, in French.",
    "request_id": "08798cfaa6b0499c",
    "limite": "monthly_transfer"
  },
  "detail": "Human readable message, in French."
}
```

- Branch on the HTTP status, `error.code` and `error.limite`, **never** on `message` (French, for humans, may change).
- Log `error.request_id` (also returned in the `X-Request-ID` response header): it identifies the request in LuluFiles support.
- `error.limite` is present when a plan limit was hit. Values: `file_size`, `server`, `monthly_transfer`, `egress`, `storage`, `files`, `applications` (number of disks), `api_keys`.
- Validation errors (`422`, code `validation_error`) also carry `error.fields`: `[{ "field": "...", "reason": "..." }]`.

| Status | `error.code` | Meaning and what to do |
|---|---|---|
| 400 | `bad_request` | Malformed request or empty file. Fix the request. |
| 401 | `unauthorized` | Missing/invalid key, or operation reserved to a dashboard session. Do not retry. |
| 403 | `cle_hors_canal` | The call names a disk other than the key's (a `folder_id`, `disk_id` or legacy `app_id` that does not match), or tries to create a disk. Do not retry: use a key issued for that disk. The message names the key's disk. |
| 403 | `lecture_seule` | Write attempt on something shared with the account in read-only mode, or on an item deposited by someone else. Do not retry. |
| 403 | `forbidden` | Signed link altered or expired. Request a new link. |
| 404 | `not_found` | Resource does not exist or does not belong to the account. |
| 409 | `conflict` | File not ready yet (still `queued`/`uploading`), retry of a file that is not `failed`, disk still containing files, restore of an item that is not in the trash. |
| 409 | `nom_deja_pris` | **Explicit rename of a folder** onto a name already used in the same parent. Folder names are unique; a folder created on a taken name is suffixed instead. Files are never concerned: they may share a name. |
| 409 | `cycle_de_dossiers` | A folder cannot be moved inside one of its own descendants. |
| 409 | `profondeur_maximale` | The move or creation would exceed 32 levels of folders. |
| 409 | `fichier_non_pret` | Only a `ready` file can be moved or copied to another disk. Wait for it. |
| 409 | `disque_different` | This caller cannot follow a background transfer (batch routes and the newer move/copy routes can). Use `POST /files/{id}/move`. |
| 410 | `gone` | Retry impossible: the temporary copy expired. Upload the file again. |
| 413 | `payload_too_large` | File larger than allowed (`limite`: `file_size` or `server`). Rejected before the body is read. Do not retry. |
| 415 | `unsupported_media_type` | Upload not sent as `multipart/form-data`. |
| 416 | `range_not_satisfiable` | `Range` header outside the file. |
| 422 | `validation_error` | Invalid fields, or multipart field not named `upload`. |
| 429 | `rate_limited` | Quota reached (`limite` present) or request rate exceeded (`Retry-After` header present). |
| 502 | `upstream_error` | Telegram refused the operation (bot removed from the channel, revoked token...). |
| 503 | `service_unavailable` | Temporary saturation (transit disk full, queue unavailable). Retry after `Retry-After` seconds. |

Retry policy:
- Retry only `429` **without** `error.limite`, `503`, and network errors, honouring `Retry-After` (seconds), otherwise with exponential backoff and jitter, capped (for example 3 to 5 attempts).
- Never retry `400`, `401`, `403`, `404`, `410`, `413`, `415`, `422`, or `429` **with** `error.limite` (a quota will not free up by retrying; surface it to the user).
- `502`: retry once later at most; if it persists, the Telegram destination is misconfigured.

---

## 6. Limits of the current plan

LuluFiles is in its launch phase: every account gets the **Lancement** plan, free, with these limits:

| Limit | Value |
|---|---|
| Monthly transfer (uploads + downloads combined) | **5 GB** per calendar month (UTC), reset on the 1st |
| Bandwidth | **2 MB/s per direction** (upload, download), shared by all concurrent requests of the account |
| Max file size | 5 GB |
| Requests | 300 per minute **per API key** |
| Disks / API keys | 25 / 20 |
| Stored volume, number of files | not limited |

Consequences you must design for:
- Uploading 4 GB leaves only 1 GB of downloads for the rest of the month. Every byte served through a signed link or a download counts, including partial (`Range`) reads; bytes not actually sent (client disconnected) are given back.
- Bandwidth is throttled, not refused: ten parallel downloads are not faster than one. Show progress, set generous client timeouts, and avoid parallelising transfers of the same account.
- Deduplicated uploads do not consume transfer volume.
- Limits can change: **read them from `GET /me/usage`**, do not hard-code them. Public grid: `GET /plans`.
- Quotas are counted **per account, not per disk**: two keys on two disks share the same 5 GB and the same bandwidth.
- Moving or copying a file **between two disks re-transfers its bytes** (read from one Telegram channel, written to the other) and therefore **counts twice** in the monthly volume. Within one disk, moving and copying are free: a copy shares the original's Telegram chunks.
- Items in the trash still count towards stored volume (their bytes are still in Telegram), but no longer towards the file count.

---

## 7. Endpoint reference (API key surface)

All request and response bodies are JSON unless stated otherwise. UUIDs are strings. Dates are ISO 8601 with timezone.

### 7.1 System (no authentication)

**`GET /health`** → `200` `{ "status": "ok" | "degraded", "version": "...", "checks": { "database": true, "redis": true, "spool": true } }`, or `503` when the service cannot work.

**`GET /config`** → server constraints:
```json
{
  "max_upload_mb": null,
  "chunk_size_mb": 18,
  "telegram_local_api": false,
  "payment_simulated": true,
  "paiements_ouverts": false,
  "default_channel_available": true,
  "plan_offert": "lancement"
}
```
`max_upload_mb` is an absolute server cap (null = only plan limits apply).

**`GET /plans`** → list of plans with `name`, `label`, `monthly_price_xof`, `max_storage_bytes`, `max_files`, `max_applications`, `max_file_size_bytes`, `max_api_keys`, `max_monthly_egress_bytes`, `max_monthly_transfer_bytes`, `bandwidth_bytes_per_second`, `requests_per_minute` (null = unlimited).

### 7.2 Account

**`GET /auth/me`** → the account the key belongs to: `{ "id", "email", "plan", ... }`. Useful to validate a key at startup.

**`GET /me/usage`** → consumption of the current month and applicable limits:
```json
{
  "plan": "lancement",
  "plan_label": "Lancement",
  "plan_offert": true,
  "period": "2026-09",
  "storage": { "used": 2097152, "limit": null, "percent": null },
  "files": { "used": 42, "limit": null, "percent": null },
  "applications": { "used": 1, "limit": 25, "percent": 4.0 },
  "api_keys": { "used": 2, "limit": 20, "percent": 10.0 },
  "monthly_egress": { "used": 734003200, "limit": null, "percent": null },
  "monthly_transfer": { "used": 1288490188, "limit": 5368709120, "percent": 24.0 },
  "requests_this_month": 1830,
  "max_file_size_bytes": 5368709120,
  "next_upload_max_bytes": 4080218932,
  "bandwidth_bytes_per_second": 2097152,
  "requests_per_minute": 300
}
```
`next_upload_max_bytes` is the largest file accepted **right now** (smallest of: max file size, remaining monthly transfer, remaining storage, server cap). `null` = no limit. Check it before uploading a large file and refuse early with a clear message.

### 7.3 Disks (Telegram destinations)

A disk points to `telegram_channel_id`:
- a channel: `-100...` or `@public_channel_name` → the bot must be an **administrator** of the channel;
- a group or supergroup: `-100...` → the bot must be a **member**;
- a private chat: the numeric user id → the user must have **started** the bot.

`bot_token` is optional: without it, the LuluFiles global bot is used; with it, your own bot (created with @BotFather) is used and must have the rights above. The token is stored encrypted and never returned.

With an API key, these routes only ever concern **the key's own disk**.

**`GET /disks?limit=200&offset=0`** → array of Disks. With a key, exactly one entry: its disk. Read `id` from there if you need the disk's UUID.

**`GET /disks/{disk_id}`** → Disk. Another disk → `403` `cle_hors_canal`.

**`PATCH /disks/{disk_id}`** body with any of `{ "name": "...", "is_default": true }` → Disk. Changing `telegram_channel_id` or `bot_token` with an API key returns `401` (dashboard only); another disk returns `403`.

**`POST /disks/{disk_id}/verify`** → `200` `{ "ok": true, "bot_username": "...", "chat_type": "channel", "chat_title": "..." }`, or `400` explaining why the bot cannot post there. Useful as a health check of the destination.

**`POST /disks`** → `403` with an API key: creating a disk is a dashboard operation. Ask me to create it and to issue a key for it. Deleting a disk is dashboard-only too.

Disk object:
```json
{ "id": "uuid", "name": "Disque 0", "telegram_channel_id": "-1001234567890", "is_default": true, "is_system": true, "has_dedicated_bot": false, "created_at": "...", "files": 12, "folders": 3, "stored_bytes": 154237 }
```

**Legacy**: `GET /apps`, `GET /apps/{id}`, `PATCH /apps/{id}`, `POST /apps/{id}/verify` and `GET /apps/{id}/files` still work and return the same objects, with `application_id` where the new routes say `disk_id`. They are deprecated; do not use them in new code.

### 7.4 Folders and navigation

A folder lives in one disk. `parent_id: null` (or `folder_id: null`) means the root of the disk. **If your product does not need folders, skip this section**: uploads without `folder_id` land at the root and everything keeps working.

Folder object:
```json
{ "id": "uuid", "disk_id": "uuid", "parent_id": null, "name": "Invoices", "created_at": "...", "updated_at": "...", "deleted_at": null }
```

**`GET /disks/{disk_id}/entries?folder_id=&sort=name|size|date&order=asc|desc&limit=50&offset=0`** → the content of one folder:
```json
{
  "disk": Disk,
  "folder": Folder,            // null at the root of the disk
  "breadcrumb": [Folder],      // from the root down to the open folder
  "folders": [Folder],
  "files": [FileOut],
  "total_folders": 3,
  "total_files": 128,
  "limit": 50,
  "offset": 0
}
```
Folders come before files and are **not** paginated (up to 500 per folder); `limit` and `offset` apply to files only. Paginating both together would make a folder disappear between two pages. `sort=name|size|date`, `order=asc|desc`.

**`GET /disks/{disk_id}/search?q=report&folder_id=&limit=&offset=`** → same shape as `/entries`, holding the files and folders of the disk whose name contains `q` (case-insensitive, at least 2 characters). Use it instead of walking the tree.

**`POST /folders`** body `{ "disk_id": "uuid", "parent_id": "uuid-or-null", "name": "Invoices" }` → `201` + Folder.

**`PATCH /folders/{folder_id}`** body `{ "name": "..." }` → Folder. `409` `nom_deja_pris` if the name is taken in the same parent.

**`POST /folders/{folder_id}/move`** and **`/copy`** body `{ "folder_id": "uuid-or-null", "disk_id": "uuid-optional" }` → the moved or copied Folder.

**`GET /folders/{folder_id}`** → the breadcrumb, from the disk root down to this folder.

**`DELETE /folders/{folder_id}`** (optional `?permanent=true`) → moves the folder and everything inside it to the trash, or deletes it for good.

Naming rules, applied to folders and files alike:
- **Folder names are unique per parent**, compared **case-insensitively**: `Photos` and `photos` are the same name in the same parent. **File names are not**: two files may share a name in the same folder, and LuluFiles never renames a file — not on upload, not on copy, not on move.
- `/ \ : * ? " < > |` and control characters cannot be stored: what you keep here must be writable on a Windows or macOS disk. A name **you type** (creating or renaming) is rejected with `422` `nom_invalide`; a name that **arrives with a file** has them replaced by a hyphen instead, so an upload never fails over a colon that is perfectly legal on Linux or Android. Names are trimmed and capped at 255 characters.
- **Collision on a folder**: a folder created on a taken name is **suffixed** (`Photos (2)`). An **explicit rename** is refused with `409` `nom_deja_pris` instead — renaming silently would be a surprise. Neither applies to files.
- **Homonym index**: when several files of one folder share a name, listings return `display_index` on each — `0` for the oldest, then `1`, `2`; `null` when the name is unique there. It is a **display aid**, computed per folder (not per page): the stored name and the downloaded name never carry it. Show it if your UI lists files, and identify files by `id`, never by name.
- Maximum depth: **32** (`409` `profondeur_maximale`). A folder cannot be moved into one of its own descendants (`409` `cycle_de_dossiers`).

Cost of moving things, which you must design for:

| Operation | Bytes transferred | Monthly volume |
|---|---|---|
| Move within one disk | none | nothing |
| Copy within one disk | none — both files share the same Telegram chunks | nothing |
| Move or copy **to another disk** | read from the source channel, written to the target channel | **counted twice** (out + in) |

A cross-disk move or copy answers **`202`** with the **new** item (a different `id`, `disk_id` = the target). Its `status` is usually `queued` — poll it like an upload — but may already be `ready` or `failed` when the server runs transfers synchronously. A failed transfer still answers `202`, with `status: "failed"` and `error_message`: read the status, not the HTTP code. A move removes the original **only after** the transfer succeeds; on failure the original stays and the new item is `failed`. A folder moved across disks recreates its tree immediately and queues its files one by one.

### 7.5 Files

File object (`FileOut`), returned by upload, status, list and retry:
```json
{
  "id": "8f3c2a0e-...",
  "disk_id": "uuid",
  "folder_id": "uuid-or-null",
  "original_filename": "report.pdf",
  "display_index": null,
  "mime_type": "application/pdf",
  "size_bytes": 51396,
  "sha256_checksum": "4b869a7d...",
  "chunk_count": 1,
  "chunks_uploaded": 0,
  "status": "queued",
  "error_message": null,
  "retryable": false,
  "created_at": "2026-09-14T10:02:11Z",
  "updated_at": "2026-09-14T10:02:11Z",
  "download_url": "/files/8f3c2a0e-.../download",
  "preview_url": "/files/8f3c2a0e-.../preview"
}
```
- `status`: `queued` (received, waiting for a worker), `uploading` (progress = `chunks_uploaded` / `chunk_count`), `ready` (downloadable), `failed` (cause in `error_message`).
- `retryable`: `true` when a `failed` file can be retried without re-uploading (the server still holds a temporary copy, kept about 24 hours), or the file came from another disk and its bytes are still in the origin channel). In both cases `POST /files/{id}/retry` resumes at the first missing chunk; nothing already delivered is sent again, and only the remaining volume is charged.
- `download_url` and `preview_url` are relative paths that **require the API key**: use them only from your backend. Give clients signed links instead.
- `original_filename` is sanitised by the server (path parts and control characters removed, max 255 chars). `mime_type` is normalised (unknown or invalid → `application/octet-stream`).

**`POST /files/upload`** (optional query `?folder_id=<uuid>`, `?disk_id=<uuid>`, or the deprecated `?app_id=<uuid>`)
- Body: `multipart/form-data` with exactly one file field named **`upload`**. Set the part's filename and Content-Type.
- The file lands in the **key's disk**: at its root by default, or in `folder_id` when you pass one. A `folder_id` (or `disk_id`, or legacy `app_id`) pointing at another disk fails with `403` `cle_hors_canal` — the call is refused, never silently redirected.
- The stored name is exactly the one you sent, sanitised (path parts and control characters removed, 255 characters max). An existing file of the same name in that folder is **not** an error and does **not** rename anything: both keep the name, and listings tell them apart with `display_index`.
- Send a `Content-Length` when you can: oversized uploads are then refused before any byte is read.
- Responses:
  - `201` + FileOut `ready`: the file is already in Telegram (synchronous server mode, or deduplicated content).
  - `202` + FileOut `queued`: accepted; a worker transfers it to Telegram. Poll its status.
  - `413`, `429` (with `limite`), `503` (with `Retry-After`), `502` (Telegram refused in synchronous mode), `400` (empty file), `415`/`422` (bad multipart).
- The request can take time: the upload is received at the account's bandwidth (2 MB/s), so a 1 GB file takes at least about 9 minutes. Configure timeouts accordingly (idle/read timeout, not a short total timeout).

**`GET /files/{file_id}`** → FileOut, for a file of the key's disk; anything else → `404`. Use it to poll after a `202`: first poll after ~1.5 s, then back off (for example 1.5 s → 5 s → 15 s), stop on `ready` or `failed`, and give up with an explicit error after a reasonable deadline (for example 30 minutes for large files). Never poll faster than once per second.

**`GET /files?limit=50&offset=0`** → every file of the key's disk, whatever its folder, newest first: `{ "items": [FileOut], "total": 128, "limit": 50, "offset": 0 }`, `limit` ≤ 200. Items in the trash are not listed. To browse folder by folder, use `GET /disks/{id}/entries` instead.

**`PATCH /files/{file_id}`** body `{ "name": "invoice-2026.pdf" }` → FileOut. `409` `nom_deja_pris` if taken in the same folder.

**`POST /files/{file_id}/move`** and **`/copy`** body `{ "folder_id": "uuid-or-null", "disk_id": "uuid-optional" }` → FileOut. Within the disk, both are instant and free; across disks, see the table in section 7.4 (`202`, `queued`, volume counted twice).

**`POST /files/{file_id}/retry`** → retries a `failed` file, resuming from the first chunk not yet in Telegram.
- `202` + FileOut `queued` (or `201` `ready` in synchronous mode): poll again.
- `409`: the file is not `failed`. `410`: temporary copy expired, upload again. `429` with `limite`: not enough monthly transfer left.

**`GET /files/{file_id}/download`** → file content as `attachment`. **`GET /files/{file_id}/preview`** → same content, `inline` when the type is safe to display. Both require the API key, support `Range` (`206 Partial Content`, `Accept-Ranges: bytes`, `ETag` = `"<sha256>"`, `If-Range`), and return `409` if the file is not `ready`. Use them for server-side processing only.

**`POST /files/{file_id}/link`** body `{ "disposition": "attachment" | "inline" }` → signed link:
```json
{ "url": "/files/8f3c.../content?u=...&disposition=inline&expires=1757844431&signature=...", "expires_at": "2026-09-14T14:07:11Z" }
```
- Absolute URL = `https://lulufiles-api.onrender.com` + `url`. No authentication needed to read it.
- Validity: 1 hour for `attachment`, 4 hours for `inline` (long enough to watch a video that keeps sending `Range` requests). Rely on `expires_at`, never on these durations.
- Supports `Range`: media seeking and resumable downloads work.
- `inline` is honoured only for safe types: raster images (png, jpeg, gif, webp, avif, bmp), audio, video, PDF, plain text. Anything else (HTML, SVG, archives...) is always served as `attachment`.
- Expired or altered link → `403`: ask your backend for a new link.
- Do not cache signed links beyond `expires_at`, do not store them in your database, do not log them (the signature is a bearer credential until it expires).
- Access is re-checked at each use: a link for a deleted file stops working.

**`DELETE /files/{file_id}`** (optional `?permanent=true`) → `{ "ok": true, "telegram_message_deleted": true | false | null }`.
- Without `permanent`, the file goes to the **trash**: it leaves every listing, keeps its bytes, and can be restored for 30 days. `telegram_message_deleted` is then `null`.
- With `?permanent=true`, the file disappears immediately and its Telegram messages are removed unless another file references them.
- `null`: nothing to remove in Telegram (chunks still used by a duplicate) or removal scheduled in the background.
- `false`: Telegram refused (bots cannot delete channel messages older than 48 hours). The content stays in the channel, but is no longer indexed.

**`GET /shared/files`** (deprecated) → files other LuluFiles users shared with this account. It still works with an API key, but only lists **file** shares, never the content of shared folders, and creating or revoking a share stays dashboard-only. See section 7.7.

---

### 7.6 Trash and batch operations

Deleting is reversible by default. An item in the trash keeps its bytes in Telegram, disappears from every listing, and is purged for good after **30 days**.

**`GET /disks/{disk_id}/trash?limit=50&offset=0`** →
```json
{ "folders": [Folder], "files": [FileOut] }
```
It lists only the **roots** of what was thrown away: a folder in the trash carries its content with it, and its children are not repeated.

**`POST /files/{file_id}/restore`** and **`POST /folders/{folder_id}/restore`** → put the item back where it was. `409` if it is not in the trash. If its original parent is gone, it returns to the disk root.

**`POST /disks/{disk_id}/trash/empty`** → permanently deletes everything in that disk's trash. Irreversible, and **dashboard only**: with an API key it answers `401`.

Batch routes apply one operation to a whole selection, up to 200 items:

**`POST /batch/move`**, **`/batch/copy`**, **`/batch/delete`**, **`/batch/restore`**
```json
// request  (move/copy also take "folder_id" and optional "disk_id"; delete takes "permanent")
{ "files": ["uuid"], "folders": ["uuid"], "folder_id": "uuid-or-null" }

// response
{
  "results": [
    { "kind": "folder", "id": "uuid", "ok": true,  "name": "Invoices" },
    { "kind": "file",   "id": "uuid", "ok": false, "code": "nom_deja_pris", "error": "..." }
  ],
  "succeeded": 1,
  "failed": 1
}
// a successful item that crossed disks also carries:
//   "new_id":    the item created in the target disk (its "id" stays the source's)
//   "status":    the least advanced state of its transfers (failed > queued > uploading > ready)
//   "transfers": how many files actually have bytes to re-send
```
**Every item gets its own outcome**: a refusal on one does not roll back the others. Report partial success to your users instead of a single "it failed".

---

### 7.7 Shares and public links (dashboard only, but you will meet them)

A LuluFiles account can share a **file** or a **folder** with another LuluFiles user (by email, read or read+write), or publish a **public link** (always read-only). **Creating a share always requires a dashboard session**, and the whole `/shares*` surface answers `401` with an API key. A leaked key therefore cannot publish anything. Two deprecated per-file routes remain open to a key for housekeeping: `GET /files/{id}/shares` lists the shares of one of its files, `DELETE /file-shares/{id}` revokes one.

What this means for your integration:

- **Do not build your product's sharing on LuluFiles shares.** Implement sharing in your own application and hand your users **signed links** (section 7.5, `POST /files/{id}/link`): they expire on their own, need no dashboard action, and you keep the authorization.
- **A folder of your disk may be shared in write mode by the account owner.** Files and folders created by such a recipient appear in your listings like any other, they record who deposited them, and that recipient may throw away what they added themselves. Their bytes count against **your** account's quotas — the disk owner pays for what lands in their channel. If that surprises your accounting, do not share your integration's folders.
- **Public links are anonymous HTTP**, and they exist whether you use them or not: `GET /share/{token}` describes the target, `GET /share/{token}/entries?folder_id=` browses a shared folder, `GET /share/{token}/download?file_id=` and `/preview?file_id=` serve one file of it. They are rate-limited per IP address, support `Range`, and every served byte counts against the owner's monthly volume. A revoked or expired link answers `403`.
- **Trash suspends a share**: while the shared file or folder is in the trash, recipients and links stop working; restoring it restores access. Nothing is revoked.

---

## 8. Implementation requirements

Build a small, well-tested LuluFiles client module on the backend, then the application endpoints that use it.

### 8.1 Backend client module

- Configuration from server-side environment: `LULUFILES_BASE_URL` (default `https://lulufiles-api.onrender.com`), `LULUFILES_API_KEY` (required, fail fast at startup if missing). No disk id is needed: the key already carries its disk. `LULUFILES_FOLDER_ID` is optional, and must belong to that disk. If the product uses several disks, configure one key per disk and select it explicitly.
- At startup, you may call `GET /disks` once and log the disk the key is bound to: it makes a misconfigured key obvious immediately.
- One reusable HTTP client with connection pooling, a connect timeout (~15 s) and a long read timeout for transfers.
- Methods: `getUsage()`, `upload(stream|file, filename, contentType, size?, folderId?)`, `getFile(id)`, `waitUntilReady(id, deadline)`, `retry(id)`, `createSignedLink(id, disposition)`, `deleteFile(id, { permanent })`, `restoreFile(id)`, `listEntries(diskId, folderId, page)`, and, if the product exposes folders, `createFolder`, `renameFolder`, `moveFolder`, `deleteFolder`.
- A typed error (`LuluFilesError`) carrying `status`, `code`, `limite`, `requestId`, `retryAfter`, and a `retryable` flag computed from the retry policy of section 5.
- Streaming uploads: never buffer a whole large file in memory. Stream from the incoming request or from a temporary file, and pass the size as `Content-Length` when known.
- Never log the API key, signed link URLs, or file contents.

### 8.2 Your database

Create a table (adapt names to the project):

| Column | Purpose |
|---|---|
| `id` | your own primary key, the id exposed to clients |
| `owner_id` | your end user |
| `lulufiles_file_id` | UUID returned by LuluFiles (never exposed as an authorization token) |
| `lulufiles_folder_id` | folder it was stored in, when you use folders (nullable = disk root) |
| `original_filename`, `mime_type`, `size_bytes`, `sha256` | copied from FileOut |
| `status` | mirrored from LuluFiles: `queued`, `uploading`, `ready`, `failed` |
| `deleted_at` | set when you trash it, so your UI can offer "restore" like LuluFiles does |
| `error_message` | last failure cause |
| `created_at`, `updated_at` | timestamps |

Expose your own ids to clients and keep the mapping server-side.

### 8.3 Application endpoints (on your backend)

1. **Upload**: authenticate the user → check your per-user quota and the file size against your own rules and `next_upload_max_bytes` → stream to `POST /files/upload?folder_id=...` (omit `folder_id` for a flat store) → store the row, **including the `original_filename` returned** (it may have been suffixed) → return your DTO with status. On `202`, update the status asynchronously (background job polling `GET /files/{id}`, or poll on client request with backoff).
2. **Status**: return your row, refreshing it from `GET /files/{id}` while it is `queued`/`uploading`.
3. **Retry**: for a `failed` + `retryable` file call `POST /files/{id}/retry`; on `410` ask the client to upload again.
4. **Download / preview**: authorize the user for this file → `POST /files/{id}/link` → return `{ url: BASE_URL + url, expiresAt }`. The client uses it directly (`<a href download>`, `<img src>`, `<video src>`, native media player, OS download manager). Request a fresh link when it expires.
5. **Delete**: authorize → `DELETE /files/{id}` → the file goes to the LuluFiles trash for 30 days. Either mirror that (soft-delete your row, offer "restore" through `POST /files/{id}/restore`) or pass `?permanent=true` and delete your row. Decide explicitly; do not leave your database and LuluFiles disagreeing. Treat `404` as already deleted.
6. **Folders (only if your product exposes them)**: create with `POST /folders`, browse with `GET /disks/{id}/entries`, rename with `PATCH`, move with `/move`. Your own tree stays the source of truth for permissions.
7. **Quota display (optional)**: expose a filtered view of `GET /me/usage` to administrators, never raw to all users.

### 8.4 Client (web and mobile)

- Upload with real progress (XHR `upload.onprogress` on web; the upload APIs of the platform on mobile), a cancel button, and a resumable UX: keep the local file reference so the user can retry after a network error.
- Check the size locally before sending, using the limit your backend exposes.
- Explain that the server-side transfer continues after the upload reaches 100%: show "processing" while the status is `queued`/`uploading`.
- Map errors to clear messages: quota reached (monthly transfer), file too large, service busy (retry later), destination misconfigured (contact support).
- Media: use signed links as the source of image/video/audio components; for large downloads on mobile, hand the signed URL to the OS download manager or a background download task so the transfer survives app backgrounding.
- Web: no API key, no direct calls to LuluFiles except loading signed URLs.

### 8.5 Tests

- Unit tests of the client module with a mocked HTTP layer: success paths, `201` vs `202`, polling to `ready` and to `failed`, retry policy (`Retry-After` honoured, quotas not retried), error parsing (`code`, `limite`, `request_id`).
- Integration tests of your endpoints with LuluFiles mocked at the HTTP boundary, including authorization (a user cannot get a link for another user's file).
- Optionally one end-to-end smoke test against a test LuluFiles disk, disabled by default.

---

## 9. Reference snippets

Adapt them to the project's language and framework; they show the exact protocol.

**cURL**
```bash
# Browse the root of the key's disk
curl -H "X-API-Key: $LULUFILES_API_KEY" "https://lulufiles-api.onrender.com/disks"
curl -H "X-API-Key: $LULUFILES_API_KEY" "https://lulufiles-api.onrender.com/disks/DISK_ID/entries"

# Create a folder
curl -X POST "https://lulufiles-api.onrender.com/folders" \
  -H "X-API-Key: $LULUFILES_API_KEY" -H "Content-Type: application/json" \
  -d '{"disk_id":"DISK_ID","parent_id":null,"name":"Invoices"}'

# Upload (201 ready, or 202 queued). Without folder_id: the root of the key's disk.
curl -X POST "https://lulufiles-api.onrender.com/files/upload?folder_id=FOLDER_ID" \
  -H "X-API-Key: $LULUFILES_API_KEY" \
  -F "upload=@report.pdf;type=application/pdf"

# Status
curl -H "X-API-Key: $LULUFILES_API_KEY" "https://lulufiles-api.onrender.com/files/FILE_ID"

# Signed link for a client
curl -X POST "https://lulufiles-api.onrender.com/files/FILE_ID/link" \
  -H "X-API-Key: $LULUFILES_API_KEY" -H "Content-Type: application/json" \
  -d '{"disposition":"inline"}'

# Trash, then restore
curl -X DELETE -H "X-API-Key: $LULUFILES_API_KEY" "https://lulufiles-api.onrender.com/files/FILE_ID"
curl -X POST   -H "X-API-Key: $LULUFILES_API_KEY" "https://lulufiles-api.onrender.com/files/FILE_ID/restore"
```

**Node.js 20+ (server side)**
```js
import { openAsBlob } from "node:fs";

const BASE = process.env.LULUFILES_BASE_URL ?? "https://lulufiles-api.onrender.com";
const KEY = process.env.LULUFILES_API_KEY;
if (!KEY) throw new Error("LULUFILES_API_KEY is required");

class LuluFilesError extends Error {
  constructor(status, body, headers) {
    super(body?.error?.message ?? `LuluFiles HTTP ${status}`);
    this.status = status;
    this.code = body?.error?.code;
    this.limite = body?.error?.limite;
    this.requestId = body?.error?.request_id ?? headers.get("x-request-id");
    this.retryAfter = Number(headers.get("retry-after")) || null;
    this.retryable = status === 503 || (status === 429 && !this.limite);
  }
}

async function call(path, init = {}) {
  const res = await fetch(BASE + path, {
    ...init,
    headers: { "X-API-Key": KEY, ...(init.headers ?? {}) },
  });
  const body = res.headers.get("content-type")?.includes("json") ? await res.json() : null;
  if (!res.ok) throw new LuluFilesError(res.status, body, res.headers);
  return { status: res.status, body };
}

// Streams a file from disk (for example a temporary file written by your upload handler).
// No disk id: the key already carries the disk. Add ?folder_id=... to store in a folder.
export async function uploadFile(path, filename, contentType) {
  const form = new FormData();
  form.append("upload", await openAsBlob(path, { type: contentType }), filename);
  const { body } = await call("/files/upload", { method: "POST", body: form });
  return body; // FileOut: status "ready" (201) or "queued" (202)
}

export async function waitUntilReady(fileId, deadlineMs = 30 * 60_000) {
  const start = Date.now();
  let delay = 1500;
  for (;;) {
    const { body } = await call(`/files/${fileId}`);
    if (body.status === "ready" || body.status === "failed") return body;
    if (Date.now() - start > deadlineMs) throw new Error("LuluFiles transfer timeout");
    await new Promise((r) => setTimeout(r, delay));
    delay = Math.min(delay * 2, 15_000);
  }
}

export async function signedLink(fileId, disposition = "attachment") {
  const { body } = await call(`/files/${fileId}/link`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ disposition }),
  });
  return { url: BASE + body.url, expiresAt: body.expires_at };
}
```

**Python (httpx, server side)**
```python
import os, time, httpx

BASE = os.environ.get("LULUFILES_BASE_URL", "https://lulufiles-api.onrender.com")
client = httpx.Client(
    base_url=BASE,
    headers={"X-API-Key": os.environ["LULUFILES_API_KEY"]},
    timeout=httpx.Timeout(connect=15, read=600, write=600, pool=30),
)

def upload(path: str, filename: str, content_type: str) -> dict:
    # No disk id: the key already carries the disk. Add ?folder_id=... to store in a folder.
    with open(path, "rb") as fh:  # streamed by httpx, not loaded in memory
        r = client.post("/files/upload", files={"upload": (filename, fh, content_type)})
    r.raise_for_status()
    return r.json()  # FileOut

def wait_until_ready(file_id: str, deadline_s: int = 1800) -> dict:
    start, delay = time.monotonic(), 1.5
    while True:
        f = client.get(f"/files/{file_id}").raise_for_status().json()
        if f["status"] in ("ready", "failed"):
            return f
        if time.monotonic() - start > deadline_s:
            raise TimeoutError("LuluFiles transfer timeout")
        time.sleep(delay)
        delay = min(delay * 2, 15)

def signed_link(file_id: str, disposition: str = "attachment") -> dict:
    r = client.post(f"/files/{file_id}/link", json={"disposition": disposition})
    r.raise_for_status()
    body = r.json()
    return {"url": BASE + body["url"], "expires_at": body["expires_at"]}
```

---

## 10. Pitfalls checklist

- [ ] The API key never reaches a browser or a mobile app.
- [ ] The multipart field is named exactly `upload`.
- [ ] `folder_id` (or `disk_id`) always belongs to the key's disk; `403` `cle_hors_canal` is surfaced, never retried.
- [ ] One key per disk; a `404` on a known file id means the key is bound to another disk.
- [ ] Files are identified by `id`, never by name: two files of one folder may share a name, and `display_index` only tells them apart on screen.
- [ ] An explicit folder rename handles `409` `nom_deja_pris` by asking for another name, not by retrying.
- [ ] Deletion semantics are decided: trash for 30 days (restorable) or `?permanent=true`; my database agrees with LuluFiles either way.
- [ ] Cross-disk moves and copies are known to answer `202`, to need polling, and to **count twice** in the monthly volume.
- [ ] Batch responses are read item by item; partial success is shown as such.
- [ ] `201` and `202` are both success; `202` requires polling until `ready` or `failed`.
- [ ] A `failed` file with `retryable: true` is retried with `POST /files/{id}/retry`, not re-uploaded; `410` means re-upload.
- [ ] Downloads for clients use signed links built as `BASE_URL + url`, refreshed after `expires_at`.
- [ ] `409` on download means "not ready yet", not "conflict to fix".
- [ ] Quota errors (`429` with `error.limite`) are shown to the user and never retried in a loop; `Retry-After` is honoured otherwise.
- [ ] Timeouts account for the 2 MB/s bandwidth cap (long read/write timeouts, idle-based client timeouts).
- [ ] Per-user quotas exist on my side, because LuluFiles quotas are shared by the whole account.
- [ ] My database keeps the mapping and the authorization; LuluFiles ids are not treated as secrets or permissions.
- [ ] Error handling relies on `status`, `error.code` and `error.limite`; `error.request_id` is logged.
- [ ] Limits are read from `GET /me/usage`, not hard-coded.

---

## 11. What I expect from you

1. Ask me, before coding, only what you cannot infer: backend language/framework, mobile/web stack, how many disks the product needs (one key per disk), whether my users need a folder tree or a flat store, and my per-user limits.
2. Propose a short integration plan: files to create or modify, database migration, environment variables, endpoints.
3. Implement the backend client module, the database changes, the endpoints and the client-side upload/download UX, following sections 3 to 10.
4. Write the tests described in section 8.5.
5. Finish with a short README section explaining configuration (environment variables, Telegram destination, key rotation) and the known limits (monthly transfer, bandwidth, signed link expiry).

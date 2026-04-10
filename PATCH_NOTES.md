# Security & Bug Fix Patch Notes
Generated: 2026-04-10

---

## Critical

- **Passwords no longer sent in URL query params** — Register and change-password endpoints now accept JSON request bodies. Passwords are never exposed in server logs or browser history.
- **Cast endpoint now requires login** — The `/cast` (Roku cast) endpoint was publicly accessible. It now requires an authenticated session.
- **Device IP validated before network requests** — The cast endpoint validates that `device_ip` is a valid IPv4 address before making any outbound ECP request, preventing SSRF.

---

## Authentication & Sessions

- **Auth token stored in HttpOnly cookie** — The access token is no longer readable by JavaScript. It is set as a secure, HttpOnly, SameSite=strict cookie on login.
- **All JS fetch calls use `credentials: 'include'`** — Every API call across all pages now relies on the browser sending the HttpOnly cookie automatically, instead of reading it via `document.cookie`. Removed all `getCookie` / `getAuthHeaders` helpers that were attempting to read inaccessible cookie values.
- **Short-lived streaming tokens** — HLS segment and playlist URLs use a separate scoped token (4-hour expiry, `aud: stream-segment`) so stream URLs cannot be used to access the general API.
- **Inactive accounts cannot log in** — Disabled users are now rejected at login instead of receiving a valid token.
- **Per-account + per-IP rate limiting** — Login attempts are throttled both by IP address and by username to slow brute-force attacks.
- **Admin status not stored in JWT** — `is_superuser` was previously embedded in the JWT payload. It is now omitted from the token entirely and checked against the database on each request.
- **Admin pages verify identity via API** — `admin_live.js` was decoding the JWT in JavaScript to check admin status (which fails when the cookie is HttpOnly). It now calls `/api/v1/auth/me` on load and redirects non-admins immediately, stopping the 401 polling loop.
- **Direct connection IP used for logging** — Login uses `request.client.host` (the real TCP connection) rather than the spoofable `X-Forwarded-For` header.

---

## HLS Streaming

- **All stream endpoints require authentication** — Playlist and segment endpoints previously allowed unauthenticated access with missing tokens. They now validate either a full access token or the scoped HLS token, returning 401 when neither is present.
- **Fixed NameError crash in stream_video()** — `ffprobe` info was not assigned before being accessed in the non-HLS fallback path. Fixed by running ffprobe before the HLS redirect check.
- **FFmpeg processes cleaned up automatically** — A background reaper task terminates transcode jobs that have been idle for 10+ minutes and removes their temp files.
- **Per-stream log files** — FFmpeg stderr is written to a dedicated temp file per stream instead of a shared log, preventing log mixing between concurrent streams.

---

## TMDB Metadata

- **Setting a TMDB ID now auto-fetches metadata** — Previously, entering a TMDB ID in the edit modal and saving would store the ID but not fetch any metadata unless the "Refresh from TMDB" checkbox was also checked. Now, saving a new or changed TMDB ID automatically triggers a full metadata refresh (poster, backdrop, overview, title, episodes for shows).

---

## Data & Models

- **Duplicate database columns removed** — `MediaItem` had duplicate `overview` and `release_date` column definitions, which caused undefined behavior in migrations.
- **Duration stored as float, not integer** — `duration_seconds` now correctly stores fractional seconds (e.g. 5412.8s) instead of truncating to whole seconds.
- **Race condition fixed on first user registration** — Two simultaneous registrations could both become admin. Fixed with an atomic `COUNT(*)` query instead of a fetch-then-check pattern.
- **Pairing codes persisted to database** — Device pairing codes are now stored in a `pairing_codes` table instead of in memory, so in-progress pairings survive a server restart.

---

## Input Validation

- **Admin-generated passwords use `secrets`** — Password resets now use `secrets.token_urlsafe(16)` instead of a predictable wordlist phrase (~5,760 combinations).
- **Input length limits on key fields** — Usernames, passwords, media titles, library names/paths, and invite codes now have enforced maximum lengths in Pydantic schemas.

---

## Frontend

- **XSS fixed in admin user list** — The user management table was built with `innerHTML` using raw server data. Rewritten to use the DOM API (`textContent`, `appendChild`) so user-controlled strings cannot inject HTML.
- **`showMessage` in pair.html uses `textContent`** — The pairing page message display was using `innerHTML`, allowing any error message content to be interpreted as HTML. Fixed to use `textContent`.

---

## Infrastructure

- **CORS restricted to explicit origins** — `allow_origins=["*"]` replaced with an allowlist driven by the `CORS_ORIGINS` environment variable (defaults to localhost only).
- **Security headers added** — All HTML responses now include `Content-Security-Policy`, `X-Content-Type-Options`, `X-Frame-Options`, and `Referrer-Policy` headers.
- **Secret key file created with owner-only permissions** — The auto-generated secret key file is now created with `0o600` permissions instead of world-readable defaults.
- **FFmpeg binary integrity verification** — After downloading FFmpeg, a SHA-256 hash is computed and saved as a local sidecar file. On every subsequent startup the binary is verified against this sidecar — a mismatch (indicating tampering or corruption) blocks use of the binary.
- **Open registration defaults to closed** — New installations default `open_registration` to `false`. Registration requires an invite code unless an admin explicitly enables open registration in settings.

# ReadItSoon Companion — Design Spec

## Overview

A macOS menu bar application (Go) that polls the ReadItSoon server for pending articles and saves their markdown content to a user-specified local directory, organized by domain. Distributed as a compile-on-demand binary with user credentials baked in.

## Architecture

Two systems:

1. **ReadItSoon (Rails)** — new API endpoints + download page that compiles the companion
2. **Companion (Go)** — macOS menu bar app, polls + downloads + marks complete

---

## Rails Side

### Database Changes

**Migration: add `downloaded_at` to articles**

```ruby
add_column :articles, :downloaded_at, :datetime
```

**New table: `companion_tokens`**

| Column     | Type      | Notes                        |
|------------|-----------|------------------------------|
| id         | bigint    | PK                           |
| email_id   | bigint    | FK to emails, indexed        |
| token      | string    | SecureRandom.hex(32), unique |
| created_at | datetime  |                              |
| updated_at | datetime  |                              |

### New Endpoints

All companion API endpoints authenticate via `Authorization: Bearer {token}` header + `email` param. Token validated against `companion_tokens`. All endpoints verify that the requested article belongs to the authenticated email (`article.email_id == token.email_id`).

#### `GET /api/companion/articles`

**Params:** `email`, `token`

**Response:** JSON array of articles where `downloaded_at IS NULL AND sent_status = 'delivered' AND markdown IS NOT NULL` for that email. Domain is extracted from the article's `url` column at response time.

```json
[
  {"id": 42, "title": "Some Article", "domain": "example.com"},
  {"id": 43, "title": "Another One", "domain": "blog.dev"}
]
```

#### `GET /api/companion/markdown/:id`

**Params:** `email`, `token`

**Response:** Raw markdown content (text/plain).

#### `POST /api/companion/articles/:id/downloaded`

**Params:** `email`, `token`

**Response:** 200 OK. Sets `downloaded_at = Time.current` on the article.

#### `GET /download-companion`

**Auth:** Only accessible to paying users (`subscription_status IN ('active', 'trialing')`).

**Page content:**
- Marketing copy:
  - "Store your reads where they matter to you"
  - "Save them in your 'second brain'"
  - "Allow your favorite agent to read them"
  - "Annotate them"
- Brief explanation: companion runs in background, polls for new articles, saves markdown files locally
- Requirements: macOS (Apple Silicon + Intel)
- Single "Download Companion" button

#### `POST /download-companion`

**Auth:** Paying user only.

**Action:**
1. Find or create `CompanionToken` for user's email
2. Compile Go binary:
   ```bash
   cd /path/to/readitsoon-companion
   CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -ldflags "-X main.baseURL=https://readitsoon.com -X main.userEmail=user@kindle.com -X main.authToken=abc123" -o /tmp/companion-arm64
   CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -ldflags "-X main.baseURL=https://readitsoon.com -X main.userEmail=user@kindle.com -X main.authToken=abc123" -o /tmp/companion-amd64
   lipo -create -output /tmp/readitsoon-companion /tmp/companion-arm64 /tmp/companion-amd64
   ```
3. Return binary as file download (`Content-Disposition: attachment; filename=readitsoon-companion`)

---

## Go Companion App

### Compile-Time Variables

```go
var (
    baseURL   string // set via -ldflags, e.g. "https://readitsoon.com"
    userEmail string // set via -ldflags
    authToken string // set via -ldflags
)
```

Endpoints derived at runtime: `baseURL + "/api/companion/articles"`, etc.

### Runtime Config

Stored at `~/.readitsoon-companion.json`:

```json
{
  "save_path": "/Users/john/Documents/ReadItSoon"
}
```

### First Run

1. **Save path prompt:** Terminal dialog asking where to save files. User provides absolute path.
2. **Service install prompt:** "Install as background service? [y/n]"
   - If yes: write LaunchAgent plist to `~/Library/LaunchAgents/com.readitsoon.companion.plist`
   - Plist runs the binary on login with no arguments (menu bar mode)

### Menu Bar

**Library:** `getlantern/systray` (or equivalent cgo-based systray library)

**Icon states:**
- Default: white silhouette of ReadItSoon logo (from `icon.svg`, converted to all-white, 22x22 template image)
- Downloading: clock emoji overlay
- Done: checkmark emoji overlay (reverts to default after 5 seconds)

**Dropdown menu:**
- Single item: "Monitoring for files sent to user@kindle.com" (uses compile-time `userEmail`)

### Polling Loop

Every 60 seconds:

1. `GET {baseURL}/api/companion/articles?email={userEmail}` with `Authorization: Bearer {authToken}` header
2. If empty array: no-op
3. If articles returned:
   - Change icon to clock state
   - Download up to 3 concurrently (buffered channel semaphore)
   - For each article:
     a. `GET {baseURL}/api/companion/markdown/{id}?email={userEmail}` with Bearer token header
     b. Save to `{savePath}/{domain}/{sanitized-title}.md` (append `-2`, `-3` etc. on filename collision)
     c. `POST {baseURL}/api/companion/articles/{id}/downloaded?email={userEmail}` with Bearer token header
   - After all downloads complete: change icon to checkmark state
   - After 5 seconds: revert icon to default

### Directory Structure

```
{savePath}/
  example.com/
    some-article-title.md
  blog.dev/
    another-article.md
```

- Domain extracted from article's source URL
- Title sanitized: lowercase, spaces to hyphens, strip non-alphanumeric except hyphens
- On filename collision: append `-2`, `-3`, etc.

### Icon Processing

Source: `/Users/grillermo/c/readitsoon/public/icon.svg`

Build step (pre-compilation or embedded):
- Convert SVG to all-white (replace all fill colors with `#FFFFFF`)
- Render at 22x22 and 44x44 (2x) as PNG
- Embed in binary as template images
- For clock/checkmark states: composite emoji text onto the icon at build time or use separate pre-rendered assets

---

## What's NOT Included

- No Windows/Linux support
- No auto-update mechanism
- No multiple accounts per binary
- No pause/resume
- No uninstall command
- No retry logic beyond basic HTTP timeout/error
- No encryption of local config (token is in binary anyway)

---

## Security Considerations

- Token is per-user, revocable by deleting the `companion_tokens` record
- API endpoints validate token+email pair on every request
- All endpoints verify article ownership (article.email_id == token.email_id)
- Credentials sent via Authorization header (not query params) to avoid log exposure
- Binary contains credentials — user should not share it
- HTTPS only for all API calls
- Rate limit: server rejects polls more frequent than 1/30s per token

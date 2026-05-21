# Article Download Flow

## Overview

User submits an article URL via bookmarklet → HTML is extracted and converted → Article is delivered to Kindle as EPUB and/or downloaded locally by the companion app.

---

## 1. Submission (Bookmarklet → API)

1. User clicks the bookmarklet on any article page.
2. Bookmarklet POSTs to `POST /preview` with:
   - `inputhtml` — raw HTML of the current page
   - `url` — article URL (query string stripped)
   - `email` — user's Kindle email
3. Server processes the HTML:
   - Sends HTML to the **Readability service** (`http://127.0.0.1:3001/extract`) — extracts `content`, `title`, `author`
   - Resolves relative URLs in HTML using the base URL (Nokogiri)
   - Converts HTML → Markdown via **Pandoc** (`pandoc -f html -t markdown-link_attributes`)
4. Server generates an **HMAC-SHA256 signature** over `url + markdown + title + author + email` using `Rails.secret_key_base`.
5. Preview is cached in **Redis** for 24h under `preview:{uuid}`.
6. Response returns rendered HTML preview, markdown, signature, and quota info.

---

## 2. Send to Kindle (API → Background Job)

1. User confirms the preview → bookmarklet POSTs to `POST /send` with markdown, title, author, url, email, and signature.
2. Server validates:
   - Signature (HMAC-SHA256 must match)
   - Email exists in DB
   - Deduplication: same article not sent in last 60s
   - Monthly quota not exceeded
3. **Article record created:**
   ```
   articles: { email_id, url, title, author, markdown, sent_status: scheduled(0) }
   ```
4. `DeliveryJob` enqueued (Solid Queue).

---

## 3. Delivery Job

1. Job fetches the Article record.
2. Appends a "report problem" footer to the markdown.
3. **EpubCreator** converts Markdown → EPUB via Pandoc:
   - Writes markdown + YAML front matter to a temp file under `working-files/`
   - Runs `pandoc article.md -o article.epub --template lib/pandoc/template.html`
4. **DeliveryService** sends the EPUB via **Mailgun**:
   - From: `SENDER_EMAIL`
   - To: user's Kindle email
   - Attachment: the `.epub` file
5. Temp directory is deleted.
6. Article record updated:
   ```
   articles: { sent_status: delivered(1), sent_at: now }
   ```

---

## 4. Companion App Polling

The companion app is a native macOS menu bar app that polls every **60 seconds**.

1. `GET /api/companion/articles?email={email}` (Bearer token auth)
   - Returns articles where `sent_status = delivered AND markdown IS NOT NULL AND downloaded_at IS NULL`
   - Response: `[{ id, title, domain }]`
2. For each pending article (up to 3 concurrent):
   - `GET /api/companion/articles/:id/markdown?email={email}` — fetches markdown as plain text
   - Saves `.md` file to `{savePath}/{domain}/{slug}.md` on disk
   - `POST /api/companion/articles/:id/downloaded?email={email}` — marks downloaded
3. Article record updated:
   ```
   articles: { downloaded_at: now }
   ```

---

## Article State Transitions

```
scheduled (0)
    ↓  DeliveryJob completes Mailgun send
delivered (1)
    ↓  Companion app marks download complete
downloaded_at set
```

---

## Database Records Mutated

| Model          | When created/mutated                            | Key fields                                              |
|----------------|-------------------------------------------------|---------------------------------------------------------|
| `Email`        | First preview for that address                  | `email`, `max_articles_per_month`, `subscription_status` |
| `Article`      | On `POST /send`                                 | `sent_status`, `sent_at`, `downloaded_at`, `markdown`   |
| `CompanionToken` | On companion app download (`POST /download-companion`) | `token`, `email_id`                          |

---

## Files Created/Deleted

| File                           | When                                      | Fate                        |
|--------------------------------|-------------------------------------------|-----------------------------|
| `working-files/{slug}.md`      | EpubCreator temp input                    | Deleted after Mailgun send  |
| `working-files/{slug}.epub`    | EpubCreator output                        | Deleted after Mailgun send  |
| `{savePath}/{domain}/{slug}.md` | Companion app saves to user's local disk | Persists on user's machine  |

No S3 or ActiveStorage — files are local and transient except for what the companion saves.

---

## External Services

| Service         | Purpose                                      |
|-----------------|----------------------------------------------|
| Readability API | Extracts article text/title/author from HTML |
| Pandoc          | HTML→Markdown and Markdown→EPUB conversion   |
| Mailgun         | Delivers EPUB to Kindle email                |
| Stripe          | Manages subscription quotas (optional)       |
| Redis           | Caches preview data (24h TTL)                |
| Solid Queue     | Background job queue for DeliveryJob         |

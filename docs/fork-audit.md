# Fork-point audit — hister

**Frozen record. Do not edit.** (See AGENTS.md failure modes.)

- **Upstream**: https://github.com/asciimoo/hister
- **Fork point**: `5c1f8a73` (`master@upstream`, post-v0.16.0, 2026-07-03)
- **Audited**: 2026-07-03, prior to first fork commit
- **Verdict**: fork it — architecture already fits the target deployment
  (remote multi-device instance); no blocking findings.

## What hister is

Self-hosted personal web search engine. ~28.5k lines of Go plus a Svelte
webui and MV3 browser extension. AGPLv3+.

- **Server core** (`server/`): HTTP API, sessions, access-token and OAuth
  (GitHub/Google/OIDC) auth, multi-user (`user_handling`), public mode,
  MCP endpoint (`/mcp`) for agents.
- **Indexer** (`server/indexer/`): Bleve full-text index, custom query
  language (`querybuilder/`), language detection (lingua-go), per-language
  stemming.
- **Metadata store**: GORM over SQLite (mattn, cgo) or Postgres (pgx).
- **Semantic search** (`server/vectorstore/`): OpenAI-compatible
  `/v1/embeddings` client with chunking; vectors in vendored sqlite-vec
  (C, cgo) or Postgres.
- **Crawler** (`server/crawler/`): plain HTTP + chromedp headless Chrome
  (CDP and BiDi), robots.txt support.
- **Extractors** (`server/extractor/`): readability, PDF, markdown/org,
  site-specific (Wikipedia, GitHub, StackExchange, JSON-LD, yt-dlp).
- **Browser extension** (`webui/ext/`): content script extracts
  title/text/html/favicon in the browser and POSTs to `/api/add`;
  search-result click capture (`/api/history`); PDF capture
  (`/api/add_pdf`); server-side skip rules polled by the extension;
  `X-Access-Token` + arbitrary custom headers for auth.
- **TUI** (bubbletea) and CLI (cobra/viper).

## Fit for the target use case (remote index, multi-device capture)

Works at fork point with zero changes: extension is configured with a
server URL + token; extraction happens client-side so the server indexes
the DOM the user actually saw (auth'd pages, SPAs) without holding user
credentials; skip rules are shared server-side across devices; `label`
lets devices tag their submissions. Multi-user via `app.user_handling`
with OAuth, or single shared `access_token`.

Gaps noted: no Safari/iOS extension; per-user vs global rules and history
semantics need verification under multi-user; MCP endpoint auth coverage
worth re-checking before exposing publicly.

## Supply-chain / packaging observations

- Nix packaging exists upstream (`flake.nix` + `nix/`): buildGoModule +
  buildNpmPackage frontend, NixOS/home-manager/darwin modules. Version
  source of truth is `webui/app/package.json`.
- Vendored C: `server/vectorstore/sqlitevec/` (sqlite-vec + sqlite3.h,
  with `update.sh`); cgo via mattn/go-sqlite3. Any upstream change to
  vendored C or `update.sh` deserves close review.
- Heavy dependency surface: chromedp/cdproto, bleve + zapx family,
  charmbracelet TUI stack, gorm, viper. Lockfile churn in upstream merges
  is the main ongoing review load.
- Upstream CI is GitHub-based; not ported (fork validates locally and
  releases via SourceHut).
- `manage.sh` and `compose.yml`/`Dockerfile` are upstream's distribution
  paths; the fork's supported path is Nix.

## Rust-port assessment (recorded for the roadmap decision)

Feasible but a rewrite, not a port. Key mappings: Bleve→Tantivy
(incompatible index format, query-language semantics must be re-derived),
GORM→sqlx/SeaORM, chromedp→chromiumoxide, readability/goquery/bluemonday→
readability-rs/scraper/ammonia, lingua-go→lingua-rs, bubbletea→ratatui.
Estimated 2–4 months solo for parity; the pragmatic middle path is a Rust
server implementing the small extension-facing API (`/api/add`,
`/api/add_pdf`, `/api/history`, `/api/rules`, `/api/document`,
`/api/delete`, search) reusing upstream's extension/webui unchanged.
Decision deferred to `docs/roadmap.md`.

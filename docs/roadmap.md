# Roadmap — hister fork

Living tracker for the fork. Record significant direction changes here.
The frozen fork-point audit is `docs/fork-audit.md`.

## Requirements

- **R1** — Remote-hosted index on a personal server; browsing context
  captured from all personal devices via the browser extension pointing
  at that server.
- **R2** — Small trusted user group: owner + close friends. Multi-user
  with real accounts (OAuth) preferred over one shared token.
- **R3** — Fully open source (AGPLv3+), fork publicly available; a
  source link on the hosted instance satisfies AGPL §13.
- **R4** — Nix-native operations: the server deploys via the flake's
  NixOS module; no Docker/compose in the fork's supported path.
- **R5** — Low-drama upstream tracking: periodic reviewed merges, never
  blind syncs (upstream is active; the merge-review skill is the gate).

## Decisions

| # | Decision | Status |
| --- | --- | --- |
| D1 | SourceHut (`~averagechris/hister`) is canonical; GitHub is read-only `upstream` | done |
| D2 | No hosted CI on push; local `nix flake check` + `.jj-lint.toml`; SourceHut builds are release-only, submitted explicitly from `builds/` | done |
| D3 | Keep the `hister` name (no rebrand) | done |
| D4 | Conventional Commits in fork history; upstream's `[enh]`/`[fix]` style not imitated | done |
| D5 | Version source of truth stays `webui/app/package.json`; releases tagged `vX.Y.Z` on SourceHut | done |
| D6 | Version numbering scheme post-fork (continue upstream's line vs. diverge — upstream will also mint 0.17.x) | **open** |
| D7 | Rust rewrite: full rewrite / API-compatible Rust server reusing upstream extension+webui / stay Go | **open** — see fork-audit assessment |

## Backlog

### Infrastructure (this change set)

- [x] jj remotes/bookmarks: `main` trunk, `master@upstream` reference
- [x] AGENTS.md fork policy + upstream review watermark
- [x] Frozen fork-point audit (`docs/fork-audit.md`)
- [x] Skills: `upstream-merge-review`, `release-process`
- [ ] Flake: repo scripts (`fetch-upstream`, `ci-*`, `prepare-release`,
      `release-tag`, `build-pages`, `publish-pages`, `release`),
      `release-artifact`, checks, `.jj-lint.toml`
- [ ] `builds/release-linux-x86_64.yml` (explicit-submit SourceHut build)
- [ ] First fork release + downloads page at
      `https://averagechris.srht.site/hister/`

### Deployment (R1/R2)

- [ ] Deploy to the remote server via `nixosModules.hister`; TLS via
      reverse proxy
- [ ] Decide auth: `user_handling` + OAuth provider vs. shared
      `access_token`; document friend onboarding
- [ ] Extension setup per device (server URL, token, per-device `label`)
- [ ] Verify multi-user semantics: per-user vs. global skip rules,
      history, and search visibility (flagged in fork-audit)
- [ ] Audit MCP endpoint auth before exposing it on the public host
- [ ] Backup story for the Bleve index + SQLite/Postgres metadata

### Product divergence (candidates, unordered)

- [ ] Trim unused surface (TUI? crawler? extractors?) to shrink the
      review/merge burden — decide what this deployment actually uses
- [ ] Semantic search: pick an embedding endpoint (self-hosted vs. API)
      or disable
- [ ] iOS/Safari capture gap: assess Safari Web Extension port or a
      share-sheet/bookmarklet fallback

### Rust question (D7)

- [ ] Decide: stay Go / incremental Rust server behind the existing
      extension API / full rewrite
- [ ] If Rust: spike Tantivy index + `/api/add` + search parity against
      the real extension as the go/no-go experiment

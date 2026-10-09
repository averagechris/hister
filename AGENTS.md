# AGENTS.md

Guidance for agents working in this repository.

## What this repo is

A fork of [asciimoo/hister](https://github.com/asciimoo/hister) — a
self-hosted, privacy-focused personal web search engine (Go backend, Bleve
full-text index, Svelte webui + browser extension). Future releases are
GitHub-only; historical SourceHut tags and artifacts remain preserved.

- **origin** — `git@github.com:averagechris/hister.git` (canonical, push here)
- **upstream** — `https://github.com/asciimoo/hister` (read-only reference)

## Fork policy

- The fork's trunk is the `main` bookmark, tracked on `origin`. Upstream's
  trunk is referenced only as `master@upstream` — never create a local
  `master` bookmark.
- `trunk()` is aliased to `main` in the repo-level jj config.
- Refresh upstream refs with `nix run .#fetch-upstream`
  (`jj git fetch --remote upstream`).
- **Never blind-merge upstream.** Review upstream changes with a
  supply-chain focus before porting anything — use the
  `upstream-merge-review` skill in `.opencode/skills/`.
- Primary deployment target is a small remote multi-device instance
  (owner + close friends), AGPLv3+, source kept public.

## Upstream review memory

**Upstream reviewed through `fca22ad4b57feba248f71dfdef3e9905f11e1726`
(`master@upstream`, 2026-10-09).** The fork-point tree at `5c1f8a73` was
audited in `docs/fork-audit.md`; the complete commit/path inventory and this
review's selective ports are recorded in
`docs/upstream-review-2026-10-09-inventory.md`. Future upstream review should
start after this commit; update this watermark when a review completes.

Standing exclusions (do not port from upstream without explicit discussion):

- Upstream GitHub release, Docker, WinGet, and GoReleaser automation (this fork
  uses the Fleet-backed manual GitHub process in `docs/release.md`)
- Docker Hub / compose-based distribution changes (Nix modules are the
  supported deployment path here)

## Failure modes

| Do not                                               | Because                                                                                                              |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Push to `upstream`                                   | Read-only reference remote                                                                                           |
| Create/track a local `master` bookmark               | Fork trunk is `main`                                                                                                 |
| Blind-merge or blanket-rebase onto `master@upstream` | Supply-chain review is mandatory                                                                                     |
| Add tag-triggered publishers or PR automation        | The release workflow is read-only and GitHub Release publication is a verified manual step                           |
| Move the build manifest to `.builds/`                | That path auto-submits on every push; it lives in `builds/` on purpose                                               |
| Edit `docs/fork-audit.md`                            | Frozen record of the fork-point audit                                                                                |

## Conventions

- **VCS**: jj (colocated). Conventional Commits (`feat:`, `fix:`, `chore:`,
  `!` for breaking) — consumed mechanically by `prepare-release` for semver
  and CHANGELOG generation. Upstream history uses `[enh]`/`[fix]` prefixes;
  do not imitate that style in fork commits.
- **Version source of truth**: `webui/app/package.json` (read by
  `nix/package.nix`). `prepare-release` bumps it (and the lockfile) —
  don't hand-edit versions elsewhere.
- **Task runner**: `nix run .#<name>` flake apps (`ci-fmt`, `ci-vet`,
  `ci-test`, `fetch-upstream`, `prepare-release`, `build-pages`,
  `publish-pages`, `release`). No Makefile/justfile;
  `manage.sh` is upstream's and is not the fork's task runner.
- **Lint gate**: `.jj-lint.toml` wires the `ci-*` apps into `jj lint`.
- **Skills source of truth**: `.opencode/skills/` in this repo. The
  `upstream-merge-review` and `release-process` skills are fork
  infrastructure — keep them in sync with the flake when release tooling
  changes.
- **Downloads/pages**: the old SourceHut page and build manifest are archival.
  Hister is in Fleet but is not in the downloads-enabled site projection, so
  there is no Pages dispatch for new releases.

## Release flow

- The routine Tiny-safe interface is exactly these two commands. Run the
  readiness check first and proceed only when it succeeds:

    nix run .#release -- --version X.Y.Z --check
    nix run .#release -- --version X.Y.Z

  `--check` is read-only: it verifies an empty `@` directly above matching
  local/remote `main`, version monotonicity, origin,
  and local/remote tag readiness. The normal command stamps the release tree,
  validates it with `ci-fmt`, `ci-vet`, `ci-test`, and `nix flake check`, then
  atomically publishes leased `main` and an annotated `vX.Y.Z` tag through
  `jj git root` (so managed jj workspaces work). It synchronizes jj and leaves
  a new empty `@` above `main`; the tag workflow owns artifact/checksum builds.
- GitHub Actions builds exactly the macOS arm64 and Linux x86_64 archive and
  checksum pairs. Follow `docs/release.md` to verify six workflow files and
  manually publish four release assets. No workflow writes a release or image.
- `prepare-release`, `build-pages`, and `publish-pages` are project-owned or
  archival tools, not routine release composition. There are no
  routine revision, skip-validation, skip-tag, skip-artifact, or skip-pages
  controls. Never run the normal command merely to test it; use `--check`.
- `builds/release-linux-x86_64.yml`, old SourceHut tags, and old artifacts are
  archival. Never submit the manifest for a future release or create a tag to
  test release automation.

## Roadmap

`docs/roadmap.md` is the living tracker (requirements, decisions, backlog).
Record significant direction changes there, not just in chat.

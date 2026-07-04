---
name: release-process
description: Review commits since the last SourceHut tag, choose the next semver version from Conventional Commit messages, update changelog/download pages, build artifacts, and publish a release tag for this fork.
allowed-tools: Bash, Read, Grep, Edit, Write
---

# Release Process

Use this skill when cutting a new release for this fork of hister.

The version source of truth is `webui/app/package.json` (read by
`nix/package.nix`). `prepare-release` bumps it, syncs the root
`package-lock.json`, updates `CHANGELOG.md`, and rewrites artifact names
in `builds/release-linux-x86_64.yml`.

## Fast path

For the normal deterministic release flow, create/use the jj release
change and run:

```bash
nix run .#release -- --version X.Y.Z
```

This prepares version metadata and `CHANGELOG.md`, runs validation, tags
and pushes `vX.Y.Z`, builds the local `.#release-artifact`, copies it
into `dist/downloads/`, and builds `dist/pages/hister-pages.tar.gz` for
SourceHut Pages.

Optional flags:

```bash
nix run .#release -- --version X.Y.Z --publish-pages
nix run .#release -- --version X.Y.Z --submit-linux-build
```

- `--publish-pages` runs `hut pages publish` for `averagechris.srht.site`
  under `/hister`.
- `--submit-linux-build` submits `builds/release-linux-x86_64.yml`; the
  build creates the Linux artifact, merges it with existing hosted
  downloads, and republishes SourceHut Pages using build-scoped
  `pages.sr.ht/PAGES:RW` OAuth.

The Linux build manifest lives in `builds/` (not `.builds/`), so
SourceHut does **not** auto-submit it on push. Releases publish pages
explicitly via `--publish-pages` and/or `--submit-linux-build`.

Use the manual steps below for more control or partial-release recovery.

## 1. Find the last release tag

```bash
jj tag list --no-pager --color=never
```

Use the latest fork `vX.Y.Z` tag as the baseline. (Upstream tags such as
`rolling` and pre-fork `vX.Y.Z` tags are not fork release baselines —
the first fork release baseline is the fork point, v0.16.0.)

## 2. Review commits since that tag

```bash
jj log -r '<last-tag>::@-' --no-pager --color=never --no-graph
```

Fork commits follow Conventional Commits.

## 3. Choose the next version from commit messages

Use the highest bump implied by commits since the last tag:

- **major** — any commit with `!` after type/scope, or a
  `BREAKING CHANGE:` footer
- **minor** — any `feat:` commit with no breaking change
- **patch** — `fix:`, `perf:`, `refactor:`, `build:`, `docs:`, `test:`,
  `chore:` when there is no higher bump

If no releasable commits exist, stop and explain why rather than tagging.

## 4. Create a version bump commit

```bash
jj new -m 'chore: bump version to X.Y.Z'
nix run .#prepare-release -- --version X.Y.Z --revision @
```

Verify:

```bash
grep '"version"' webui/app/package.json
grep '^## vX.Y.Z' CHANGELOG.md
```

## 5. Validate before tagging

```bash
nix flake check --no-write-lock-file
nix run .#ci-vet
nix run .#ci-test
```

All must pass before proceeding.

## 6. Tag and push

```bash
nix run .#release-tag
```

Tags `@` by default; if sitting on a fresh empty child change, pass the
release revision:

```bash
nix run .#release-tag -- --revision @-
```

## 7. Move main bookmark

```bash
jj bookmark set main --revision vX.Y.Z
jj git push --remote origin --bookmark main
```

## 8. Build artifacts and pages

```bash
nix build .#release-artifact --out-link result-release-artifact
mkdir -p dist/downloads
cp -p result-release-artifact/* dist/downloads/
```

For Linux, submit a SourceHut build after the manifest has the release
version:

```bash
hut builds submit builds/release-linux-x86_64.yml \
  --note 'hister vX.Y.Z linux release' \
  --tags 'hister/vX.Y.Z/release' \
  --visibility unlisted
```

For a local/manual pages publish:

```bash
nix run .#build-pages -- --include-existing-downloads
nix run .#publish-pages
```

Pages default to `https://averagechris.srht.site/hister/`. Keep
`CHANGELOG.md`, the downloads page, and README links in sync.

## 9. Suggested prompts

- "Review commits since the last tag and tell me the next release version"
- "Choose the next semver bump from Conventional Commit messages"
- "Prepare this fork for release"

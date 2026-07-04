---
name: upstream-merge-review
description: Evaluate new upstream GitHub changes before merging them into the SourceHut fork. Use when syncing this fork with upstream.
allowed-tools: Bash, Read, Grep
---

# Upstream Merge Review Workflow

This repository treats GitHub as `upstream` and SourceHut as `origin`.
The fork's trunk is the `main` bookmark; upstream's trunk is
`master@upstream`. Check the "Upstream review memory" watermark in
AGENTS.md before starting — review only commits after it.

## 1. Refresh upstream refs

```bash
nix run .#fetch-upstream
```

In jj, Git's `refs/remotes/upstream/master` appears as `master@upstream`.

## 2. Review what upstream added

```bash
jj log -r 'main::master@upstream' --no-pager --color=never --no-graph
jj show master@upstream --stat --no-pager --color=never
jj diff --from main --to master@upstream --no-pager --color=never
```

Focus on supply-chain risk before merging:

- new install/update paths, scripts, hooks, and generated artifacts
- release, CI, and packaging changes (`flake.nix`, `nix/`, `manage.sh`,
  Dockerfile/compose — the latter two are upstream-only distribution paths)
- network access, auth, and credential handling (extension, OAuth,
  access tokens, MCP endpoint)
- vendored C changes (`server/vectorstore/sqlitevec/`, its `update.sh`)
- dependency and lockfile churn (`go.mod`/`go.sum`,
  `package-lock.json`) — flag new or replaced modules explicitly

Respect the standing exclusions listed in AGENTS.md (GitHub CI/release
automation, Docker distribution changes).

## 3. Check local divergence

```bash
jj log -r 'master@upstream::main' --no-pager --color=never --no-graph
jj diff --from master@upstream --to main --no-pager --color=never
```

Classify local changes as one of:

1. Fork-only infrastructure/hardening that must be preserved
2. Temporary divergence that should be dropped
3. Conflicting behavior that needs a manual resolution plan

## 4. Merge only after review

Preferred policy:

1. summarize upstream commits and changed files
2. call out risky changes explicitly
3. propose a merge strategy before running mutating jj commands
4. after merge/rebase, run `nix run .#ci-vet`, `nix run .#ci-test`, and
   `nix build`, then inspect the resulting diff against `master@upstream`
5. update the "Upstream review memory" watermark in AGENTS.md with the
   new reviewed-through commit and date

## 5. Suggested prompts

- "Review upstream changes since our last sync"
- "Is it safe to merge upstream/master into our fork?"
- "Preserve our fork infrastructure and propose the cleanest jj merge plan"

---
name: release-process
description: Check and run Hister's fail-closed manual GitHub release process.
allowed-tools: Bash, Read, Grep
---

# Release Process

Future releases are GitHub-only. The version source of truth remains
`webui/app/package.json`; the project-owned `prepare-release` app stamps it,
`package-lock.json`, and `CHANGELOG.md`.

## Routine interface

```bash
nix run .#release -- --version X.Y.Z --check
nix run .#release -- --version X.Y.Z
```

Run both from an empty `@` aligned with local and remote `main`. `--check` is a
nonmutating ref/version preflight only. The real command validates the prepared
tree with `ci-fmt`, `ci-test`, `ci-vet`, and `nix flake check`, then atomically
pushes leased `main` and its annotated tag. The read-only tag workflow builds
and verifies the artifact/checksum pairs. There are no release-stage bypass
flags.

The tag workflow is read-only. It validates the trusted repository, annotated
remote tag and selected commit, then calls the SHA-pinned Fleet workflow for
`aarch64-darwin` and `x86_64-linux`. Follow `docs/release.md` to verify the six
downloaded files and manually publish only the four archives and checksum
sidecars. Hister has no Fleet Pages route, so do not dispatch one.

The SourceHut build manifest, tags, artifacts, and downloads page are archival.
Never submit the manifest or dual-publish a future tag. Never create a tag to
test this process.

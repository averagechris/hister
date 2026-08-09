---
name: release-process
description: Check and run Hister's Tiny-safe custom SourceHut release orchestration.
allowed-tools: Bash, Read, Grep
---

# Release Process

The version source of truth is `webui/app/package.json`. Releases are Nix-built
and published to SourceHut. Do not hand-compose routine releases from the
lower-level `prepare-release`, `release-tag`, `build-pages`, or `publish-pages`
apps.

## Routine interface

Choose `X.Y.Z` from Conventional Commits since the previous fork release, then
run the non-mutating readiness check:

```bash
nix run .#release -- --version X.Y.Z --check
```

Only after it succeeds, run:

```bash
nix run .#release -- --version X.Y.Z
# Include the explicit Linux job when wanted:
nix run .#release -- --version X.Y.Z --submit-linux-build
```

These are the only routine controls: version, check, and optional Linux build.
There are deliberately no revision or skip controls.

## Guarantees

The check requires a managed-workspace-safe jj Git repository, an empty `@`
whose parent equals local and remote `main`, a configured origin, SourceHut
authentication, a valid non-downgrade version, and no conflicting local or
remote tag. It does not edit files, create commits/tags, or publish anything.

The normal command:

1. stamps package/lock/changelog/Linux metadata with `prepare-release`;
2. validates that prepared tree with `ci-fmt`, `ci-vet`, `ci-test`, and
   `nix flake check`;
3. builds exactly one local release tarball and verifies its checksum;
4. creates an annotated `vX.Y.Z` tag and atomically pushes it with leased
   `main` via the backing repository returned by `jj git root`;
5. imports the refs, sets `main`, and creates a fresh empty child;
6. uploads only missing exact artifact names and idempotently requests the
   downloads refresh and optional Linux job using stable build tags.

If publication succeeded and post-publication work failed, rerun the exact same
version/options. Resume is accepted only when the annotated tag peels to remote
and local `main`, the empty working-copy parent, and the current version.
Anything else fails closed. Prepublication failures leave remote refs unchanged;
inspect or abandon the prepared `@` before retrying.

The Linux manifest lives in `builds/`, never `.builds/`. It verifies that HEAD
is exactly its annotated package-version tag and verifies checksums before its
own idempotent uploads and refresh request.

# Release process

Future Hister releases are GitHub-only. The SHA-pinned `averagechris/fleet`
GitHub helper preserves Hister's project-owned release preparation and gates,
then atomically publishes `main` and its annotated `vX.Y.Z` tag to
`averagechris/hister`. The tag starts `.github/workflows/release.yml`, which
builds `aarch64-darwin` on `macos-14` and `x86_64-linux` on `ubuntu-24.04` with
read-only repository permission. It uses `.#release-artifact`, which contains
the unwrapped `hister` binary plus README, license, and changelog.

Each Actions artifact contains one Hister archive, its checksum sidecar, and a
`release-identity-<platform>` file. A successful run therefore produces six
files. The identity files are verification evidence, not release assets. The
operator publishes only the two archives and two checksum sidecars.

## Prepare and build

```bash
nix run .#release -- --version X.Y.Z --check
nix run .#release -- --version X.Y.Z
```

Run both commands from a fresh empty `@` whose parent exactly matches local
`main` and `main@origin`. `--check` only checks refs and versions. The real
command updates `webui/app/package.json`, `package-lock.json`, and
`CHANGELOG.md`; validates the prepared Go and Nix tree; creates an annotated
tag; and atomically pushes the release commit and tag. The read-only GitHub
workflow then builds and verifies the artifact/checksum pairs for manual
publication. The local command does not build artifacts, create a GitHub
Release, or upload assets.

The workflow does not run on a `main` push. To recover an existing release,
dispatch `release.yml` from `main` with its existing tag. The tag must match
`vX.Y.Z`, be annotated on `origin`, and peel to an ancestor of the selected
`main`. Tag pushes require the event SHA to equal the peeled commit. Forks,
pull requests, malformed tags, lightweight tags, and mismatched refs fail.

## Publish the verified artifacts

1. Open the successful run named `Build release artifacts (manual publication
   required)` in `averagechris/hister`. Confirm its event and selected ref.
2. Resolve the remote annotated tag with the GitHub API. Record both the tag
   object ID and its peeled commit ID.
3. Download `release-aarch64-darwin` and `release-x86_64-linux` into a new empty
   directory. Require exactly these six files:

   ```text
   hister-vX.Y.Z-aarch64-darwin.tar.gz
   hister-vX.Y.Z-aarch64-darwin.tar.gz.sha256
   release-identity-aarch64-darwin
   hister-vX.Y.Z-x86_64-linux.tar.gz
   hister-vX.Y.Z-x86_64-linux.tar.gz.sha256
   release-identity-x86_64-linux
   ```

4. Check each sidecar with `shasum -a 256 -c`. Each identity file must contain
   exactly two lines: the recorded tag object ID, then the peeled commit ID.
5. Search all releases through the GitHub API, including drafts, for the tag.
   If none exists, recheck tag identity and create a draft with
   `gh release create --verify-tag --draft --notes-from-tag`. Upload only the
   four archives and sidecars, without `--clobber`.
6. If a draft exists, download every asset and compare its bytes with the
   verified local file. Upload only missing expected assets. Stop for unexpected
   names, mismatched bytes, or an already-public release.
7. Download the draft through the API into another empty directory. Require
   exactly the four expected names, compare every remote file byte-for-byte,
   and check both remote sidecar digests again.
8. Resolve the remote tag again. Undraft only if its object and peeled commit
   still match and all four remote assets passed byte and digest checks.

Hister is registered operationally in Fleet but is not in the downloads-enabled
site registry/presentation. There is no Pages route yet; do not dispatch or
fabricate one after publication.

## Historical SourceHut releases

Existing SourceHut tags, artifacts, and downloads remain historical records.
`builds/release-linux-x86_64.yml` is archival and must not be submitted for a
new release. Do not dual-publish future tags. Never create or push a release
tag merely to test this process.

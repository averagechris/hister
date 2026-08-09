#!/usr/bin/env bash
set -euo pipefail

export TERM=dumb

if [[ -n "${RELEASE_NIX:-}" ]]; then
  nix() { "$RELEASE_NIX" "$@"; }
fi
if [[ -n "${RELEASE_SRHT:-}" ]]; then
  srht() { "$RELEASE_SRHT" "$@"; }
else
  srht() { nix run --inputs-from . fleet#srht -- "$@"; }
fi

usage() {
  cat <<'EOF'
usage: release --version X.Y.Z [--check] [--submit-linux-build]

  --version X.Y.Z       required release version
  --check               verify release readiness without editing files or publishing refs
  --submit-linux-build  submit the Linux release build after publication
EOF
}

version=""
check_only=0
submit_linux_build=0
linux_manifest="builds/release-linux-x86_64.yml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --check) check_only=1; shift ;;
    --submit-linux-build) submit_linux_build=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$version" ]] || { printf '%s\n' '--version X.Y.Z is required' >&2; exit 2; }
[[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'invalid semver version: %s\n' "$version" >&2; exit 2; }
version="${version#v}"
tag="v$version"

repo_root="$(jj root 2>/dev/null)" || { printf '%s\n' 'release requires a jj repository' >&2; exit 1; }
cd "$repo_root"
git_dir="$(jj git root 2>/dev/null)" || { printf '%s\n' 'release requires a jj Git-backed repository' >&2; exit 1; }
[[ -d "$git_dir" ]] || { printf 'jj Git backing directory does not exist: %s\n' "$git_dir" >&2; exit 1; }
git --git-dir="$git_dir" remote get-url origin >/dev/null || { printf '%s\n' 'origin remote is not configured' >&2; exit 1; }

wc_empty="$(jj log -r @ --no-graph --color=never -T 'if(empty, "1", "0")')"
wc_commit="$(jj log -r @ --no-graph --color=never -T commit_id)"
base="$(jj log -r '@-' --no-graph --color=never -T commit_id 2>/dev/null)" || { printf '%s\n' 'cannot resolve @-' >&2; exit 1; }
local_main="$(jj log -r main --no-graph --color=never -T commit_id 2>/dev/null)" || { printf '%s\n' 'cannot resolve local main' >&2; exit 1; }
remote_main_line="$(git --git-dir="$git_dir" ls-remote --heads origin refs/heads/main)"
remote_main="${remote_main_line%%$'\t'*}"
[[ -n "$remote_main" ]] || { printf '%s\n' 'origin main does not resolve' >&2; exit 1; }
current="$(python3 - <<'PY'
import json
print(json.load(open("webui/app/package.json"))["version"])
PY
)"
CURRENT="$current" REQUESTED="$version" python3 - <<'PY'
import os, re
def semver(name):
    value = os.environ[name].removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise SystemExit(f"invalid {name.lower()} semver: {value}")
    return tuple(map(int, value.split(".")))
if semver("REQUESTED") < semver("CURRENT"):
    raise SystemExit("refusing version downgrade")
PY

remote_tags="$(git --git-dir="$git_dir" ls-remote --tags origin)"
remote_tag_object="$(printf '%s\n' "$remote_tags" | python3 -c 'import sys; ref=f"refs/tags/{sys.argv[1]}"; print(next((line.split()[0] for line in sys.stdin if line.split()[1:]==[ref]),""))' "$tag")"
remote_tag_commit="$(printf '%s\n' "$remote_tags" | python3 -c 'import sys; ref=f"refs/tags/{sys.argv[1]}^{{}}"; print(next((line.split()[0] for line in sys.stdin if line.split()[1:]==[ref]),""))' "$tag")"
resume=0
resume_needs_sync=0
if [[ -n "$remote_tag_object" ]]; then
  if [[ -n "$remote_tag_commit" && "$remote_tag_commit" == "$remote_main" && "${current#v}" == "$version" && "$wc_empty" == 1 && "$remote_main" == "$local_main" && "$local_main" == "$base" ]]; then
    resume=1
  elif [[ -n "$remote_tag_commit" && "$remote_tag_commit" == "$remote_main" && "${current#v}" == "$version" && "$wc_empty" == 0 && "$wc_commit" == "$remote_tag_commit" ]]; then
    # Publication won but local jj bookkeeping did not finish. A normal rerun
    # repairs that exact state before resuming post-publication work; --check
    # remains read-only and intentionally requires the normalized empty child.
    resume=1
    resume_needs_sync=1
  else
    printf 'existing tag %s is not an exact resumable release (peeled=%s remote-main=%s local-main=%s base=%s wc=%s current-version=%s)\n' \
      "$tag" "${remote_tag_commit:-unpeeled}" "$remote_main" "$local_main" "$base" "$wc_commit" "$current" >&2
    exit 1
  fi
else
  [[ "$wc_empty" == 1 ]] || { printf '%s\n' 'working-copy commit @ is not empty; finish it before release' >&2; exit 1; }
  [[ "$base" == "$local_main" && "$base" == "$remote_main" ]] || {
    printf 'stale/diverged checkout: @-=%s local main=%s origin main=%s\n' "$base" "$local_main" "$remote_main" >&2
    exit 1
  }
fi
if [[ $resume -eq 0 ]] && git --git-dir="$git_dir" show-ref --verify --quiet "refs/tags/$tag"; then
  printf 'local tag exists without matching remote release: %s\n' "$tag" >&2
  exit 1
fi

srht auth status >/dev/null
[[ $submit_linux_build -eq 0 || -f "$linux_manifest" ]] || { printf 'Linux manifest not found: %s\n' "$linux_manifest" >&2; exit 1; }
mode=release
[[ $resume -eq 1 ]] && mode=resume
if [[ $check_only -eq 1 && $resume_needs_sync -eq 1 ]]; then
  printf '%s\n' 'working-copy commit @ is not empty; rerun the exact release command to finish published-state synchronization' >&2
  exit 1
fi
printf 'Release plan (%s):\n  repo: %s\n  base/local/remote main: %s\n  version/tag: %s / %s\n  validation: ci-fmt, ci-vet, ci-test, nix flake check\n  artifact: .#release-artifact (tarball + checksum)\n  remote actions: %sartifact upload, refresh%s\n' \
  "$mode" "$repo_root" "$base" "$version" "$tag" "$([[ $resume -eq 0 ]] && printf 'atomic main + annotated tag, ' || true)" "$([[ $submit_linux_build -eq 1 ]] && printf ', Linux build' || true)"
[[ $check_only -eq 0 ]] || exit 0

mutated=0
tag_created=0
published=$resume
release_tmpdir="$(mktemp -d)"
on_exit() {
  status=$?
  rm -rf "$release_tmpdir"
  if [[ $status -ne 0 && $tag_created -eq 1 && $published -eq 0 ]]; then
    git --git-dir="$git_dir" tag -d "$tag" >/dev/null 2>&1 || true
    jj git import >/dev/null 2>&1 || true
  fi
  if [[ $status -ne 0 && $mutated -eq 1 && $published -eq 0 ]]; then
    printf '%s\n' 'release aborted after version stamping; inspect with "jj diff" or discard the preparation with "jj abandon @"' >&2
  fi
  exit "$status"
}
trap on_exit EXIT

if [[ $resume_needs_sync -eq 1 ]]; then
  jj git import
  jj bookmark set main --revision "$remote_tag_commit"
  jj new "$remote_tag_commit"
fi

if [[ $resume -eq 0 ]]; then
  mutated=1
  nix run .#prepare-release -- --version "$version"
  nix run .#ci-fmt < /dev/null
  nix run .#ci-vet < /dev/null
  nix run .#ci-test < /dev/null
  nix flake check --no-write-lock-file < /dev/null
  prepared_version="$(python3 -c 'import json; print(json.load(open("webui/app/package.json"))["version"])')"
  [[ "$prepared_version" == "$version" ]] || { printf 'prepared version mismatch: expected %s, got %s\n' "$version" "$prepared_version" >&2; exit 1; }
fi

artifact_dir="$(nix build .#release-artifact --no-link --print-out-paths)"
artifacts=("$artifact_dir"/*.tar.gz)
[[ ${#artifacts[@]} -eq 1 && -f "${artifacts[0]}" && -f "${artifacts[0]}.sha256" ]] || {
  printf '%s\n' 'expected exactly one release tarball and checksum' >&2
  exit 1
}
(cd "$artifact_dir" && sha256sum -c "$(basename "${artifacts[0]}").sha256")

if [[ $resume -eq 0 ]]; then
  jj describe -m "chore: release $tag"
  commit="$(jj log -r @ --no-graph --color=never -T commit_id)"
  git --git-dir="$git_dir" -c tag.gpgSign=false tag -a "$tag" -m "hister $tag" "$commit"
  tag_created=1
  git --git-dir="$git_dir" push --atomic --force-with-lease="refs/heads/main:$remote_main" origin \
    "$commit:refs/heads/main" "refs/tags/$tag:refs/tags/$tag"
  published=1
  jj git import
  jj bookmark set main --revision "$commit"
  jj new "$commit"
else
  commit="$remote_tag_commit"
fi

existing="$(srht --json git artifact list -r hister --rev "$tag")"
for artifact in "${artifacts[0]}" "${artifacts[0]}.sha256"; do
  name="$(basename "$artifact")"
  if ARTIFACTS="$existing" NAME="$name" python3 -c 'import json,os,sys; data=json.loads(os.environ["ARTIFACTS"]); names=[item["filename"] for item in data["items"]]; sys.exit(0 if os.environ["NAME"] in names else 1)'; then
    printf 'artifact already uploaded: %s\n' "$name"
  else
    srht git artifact upload -r hister --rev "$tag" "$artifact"
  fi
done

submit_build_once() {
  build_tag="$1"
  manifest="$2"
  note="$3"
  jobs="$(srht --json builds list --all --tag "$build_tag")"
  if JOBS="$jobs" python3 -c 'import json,os,sys; failed={"failed","cancelled"}; statuses=[str(x["status"]).lower() for x in json.loads(os.environ["JOBS"])["items"]]; sys.exit(0 if any(s not in failed for s in statuses) else 1)'; then
    printf 'build already active or successful: %s\n' "$build_tag"
  else
    srht builds submit "$manifest" --secrets --note "$note" --tag "$build_tag"
  fi
}

refresh_manifest="$release_tmpdir/refresh.yml"
cat > "$refresh_manifest" <<EOF
image: nixos/unstable
arch: x86_64
oauth: pages.sr.ht/PAGES:RW
environment:
  TRIGGER_SOURCE: release
  TRIGGER_PROJECT: hister
  TRIGGER_TAG: $tag
  TRIGGER_SHA: $commit
sources:
  - https://git.sr.ht/~averagechris/averagechris.srht.site
tasks:
  - refresh: |
      cd averagechris.srht.site
      nix run .#refresh-pages
EOF
submit_build_once "hister/$tag/refresh" "$refresh_manifest" "site refresh: hister $tag"
if [[ $submit_linux_build -eq 1 ]]; then
  submit_build_once "hister/$tag/linux" "$linux_manifest" "hister $tag linux release"
fi

trap - EXIT
rm -rf "$release_tmpdir"

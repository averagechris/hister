"""Network-free behavioral tests for the custom release orchestrator."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


RELEASE = Path(os.environ.get("RELEASE_SCRIPT", Path(__file__).parents[1] / "scripts" / "release.sh"))


def run(*args: str, cwd: Path, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, env=env, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class ReleaseBehavior(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.origin = self.root / "origin.git"
        self.repo = self.root / "repo"
        run("git", "init", "--bare", str(self.origin), cwd=self.root)
        run("git", "init", "-b", "main", str(self.repo), cwd=self.root)
        run("git", "config", "user.name", "Release Test", cwd=self.repo)
        run("git", "config", "user.email", "release@example.invalid", cwd=self.repo)
        (self.repo / "webui/app").mkdir(parents=True)
        (self.repo / "builds").mkdir()
        (self.repo / "webui/app/package.json").write_text('{"name":"hister","version":"1.0.0"}\n')
        (self.repo / "package-lock.json").write_text('{"packages":{"webui/app":{"name":"@hister/app","version":"1.0.0"}}}\n')
        (self.repo / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n")
        (self.repo / "builds/release-linux-x86_64.yml").write_text("image: nixos/unstable\n")
        run("git", "add", ".", cwd=self.repo)
        run("git", "commit", "-m", "feat: initial release source", cwd=self.repo)
        run("git", "remote", "add", "origin", str(self.origin), cwd=self.repo)
        run("git", "push", "-u", "origin", "main", cwd=self.repo)
        run("jj", "git", "init", "--colocate", cwd=self.repo)
        run("jj", "new", "main", cwd=self.repo)

        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        artifact = self.artifacts / "hister-v1.1.0-test.tar.gz"
        artifact.write_bytes(b"release artifact")
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        (self.artifacts / f"{artifact.name}.sha256").write_text(f"{digest}  {artifact.name}\n")
        self.log = self.root / "calls.log"
        self.state = self.root / "srht-state.json"
        self.state.write_text(json.dumps({"artifacts": [], "jobs": []}))
        self._write_fakes()
        self.env = os.environ.copy()
        self.env.update(
            RELEASE_NIX=str(self.bin / "nix"),
            RELEASE_SRHT=str(self.bin / "srht"),
            RELEASE_TEST_LOG=str(self.log),
            RELEASE_TEST_ARTIFACT_DIR=str(self.artifacts),
            RELEASE_TEST_SRHT_STATE=str(self.state),
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_fakes(self) -> None:
        nix = self.bin / "nix"
        nix.write_text(textwrap.dedent("""\
            #!/usr/bin/env python3
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["RELEASE_TEST_LOG"], "a") as log: log.write("nix " + " ".join(args) + "\\n")
            step = " ".join(args[:2])
            if os.environ.get("RELEASE_TEST_FAIL") == step:
                raise SystemExit(23)
            if args[:2] == ["run", ".#prepare-release"]:
                version = args[-1]
                package = pathlib.Path("webui/app/package.json")
                data = json.loads(package.read_text()); data["version"] = version; package.write_text(json.dumps(data) + "\\n")
                lock = pathlib.Path("package-lock.json"); data = json.loads(lock.read_text()); data["packages"]["webui/app"]["version"] = version; lock.write_text(json.dumps(data) + "\\n")
                pathlib.Path("release-stamp").write_text(version + "\\n")
            elif args and args[0] == "build":
                if os.environ.get("RELEASE_TEST_BAD_ARTIFACT") == "1":
                    bad = pathlib.Path(os.environ["RELEASE_TEST_ARTIFACT_DIR"]) / "bad"; bad.mkdir(exist_ok=True); print(bad)
                else:
                    print(os.environ["RELEASE_TEST_ARTIFACT_DIR"])
        """))
        nix.chmod(0o755)

        srht = self.bin / "srht"
        srht.write_text(textwrap.dedent("""\
            #!/usr/bin/env python3
            import json, os, pathlib, sys
            args = sys.argv[1:]
            with open(os.environ["RELEASE_TEST_LOG"], "a") as log: log.write("srht " + " ".join(args) + "\\n")
            state_path = pathlib.Path(os.environ["RELEASE_TEST_SRHT_STATE"])
            state = json.loads(state_path.read_text())
            if args[:2] == ["auth", "status"]:
                raise SystemExit(0)
            if "artifact" in args and "list" in args:
                print(json.dumps({"items": [{"filename": name} for name in state["artifacts"]]})); raise SystemExit(0)
            if "artifact" in args and "upload" in args:
                state["artifacts"].append(pathlib.Path(args[-1]).name); state_path.write_text(json.dumps(state)); raise SystemExit(0)
            if "builds" in args and "list" in args:
                tag = args[args.index("--tag") + 1]
                print(json.dumps({"items": [{"status": "SUCCESS"}] if tag in state["jobs"] else []})); raise SystemExit(0)
            if "builds" in args and "submit" in args:
                tag = args[args.index("--tag") + 1]
                state["jobs"].append(tag); state_path.write_text(json.dumps(state)); raise SystemExit(0)
            raise SystemExit("unexpected srht arguments: " + repr(args))
        """))
        srht.chmod(0o755)

    def release(self, *extra: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
        return run("bash", str(RELEASE), "--version", "1.1.0", *extra, cwd=self.repo, env=env or self.env, check=check)

    def remote_refs(self) -> str:
        return run("git", "show-ref", cwd=self.origin).stdout

    def test_check_is_read_only_and_requires_empty_main_based_working_copy(self) -> None:
        before_status = run("jj", "status", "--no-pager", "--color=never", cwd=self.repo).stdout
        before_refs = self.remote_refs()
        result = self.release("--check")
        self.assertIn("Release plan (release)", result.stdout)
        self.assertEqual(before_status, run("jj", "status", "--no-pager", "--color=never", cwd=self.repo).stdout)
        self.assertEqual(before_refs, self.remote_refs())
        self.assertNotIn("nix ", self.log.read_text())

        (self.repo / "dirty").write_text("x")
        failed = self.release("--check", check=False)
        self.assertNotEqual(0, failed.returncode)
        self.assertIn("working-copy commit @ is not empty", failed.stderr)

    def test_validation_and_artifact_failures_do_not_publish(self) -> None:
        before = self.remote_refs()
        env = self.env | {"RELEASE_TEST_FAIL": "run .#ci-vet"}
        self.assertNotEqual(0, self.release(env=env, check=False).returncode)
        self.assertEqual(before, self.remote_refs())
        self.assertNotIn("refs/tags/v1.1.0", self.remote_refs())

        run("jj", "abandon", "@", cwd=self.repo)
        run("jj", "new", "main", cwd=self.repo)
        env = self.env | {"RELEASE_TEST_BAD_ARTIFACT": "1"}
        self.assertNotEqual(0, self.release(env=env, check=False).returncode)
        self.assertEqual(before, self.remote_refs())
        self.assertNotIn("refs/tags/v1.1.0", self.remote_refs())

    def test_atomic_push_rejection_leaves_main_and_tag_unchanged(self) -> None:
        hook = self.origin / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nwhile read old new ref; do [ \"$ref\" != refs/tags/v1.1.0 ] || exit 1; done\n")
        hook.chmod(0o755)
        before = self.remote_refs()
        failed = self.release(check=False)
        self.assertNotEqual(0, failed.returncode)
        self.assertEqual(before, self.remote_refs())
        self.assertNotIn("refs/tags/v1.1.0", self.remote_refs())

    def test_atomic_annotated_publication_resume_and_empty_child(self) -> None:
        self.release("--submit-linux-build")
        remote_main = run("git", "rev-parse", "refs/heads/main", cwd=self.origin).stdout.strip()
        tag_type = run("git", "cat-file", "-t", "refs/tags/v1.1.0", cwd=self.origin).stdout.strip()
        tag_commit = run("git", "rev-parse", "refs/tags/v1.1.0^{}", cwd=self.origin).stdout.strip()
        self.assertEqual("tag", tag_type)
        self.assertEqual(remote_main, tag_commit)
        self.assertEqual("true", run("jj", "log", "-r", "@", "--no-graph", "-T", "empty", cwd=self.repo).stdout)
        self.assertEqual(remote_main, run("jj", "log", "-r", "@-", "--no-graph", "-T", "commit_id", cwd=self.repo).stdout)
        state = json.loads(self.state.read_text())
        self.assertEqual({"hister-v1.1.0-test.tar.gz", "hister-v1.1.0-test.tar.gz.sha256"}, set(state["artifacts"]))
        self.assertEqual({"hister/v1.1.0/refresh", "hister/v1.1.0/linux"}, set(state["jobs"]))

        self.log.write_text("")
        resumed = self.release("--submit-linux-build")
        self.assertIn("Release plan (resume)", resumed.stdout)
        calls = self.log.read_text()
        self.assertNotIn(".#prepare-release", calls)
        self.assertNotIn("artifact upload", calls)
        self.assertNotIn("builds submit", calls)

        run("git", "update-ref", "refs/heads/main", f"{remote_main}^", cwd=self.origin)
        mismatch = self.release("--check", check=False)
        self.assertNotEqual(0, mismatch.returncode)
        self.assertIn("not an exact resumable release", mismatch.stderr)

    def test_exact_published_commit_repairs_interrupted_jj_bookkeeping(self) -> None:
        self.release()
        remote_main = run("git", "rev-parse", "refs/heads/main", cwd=self.origin).stdout.strip()
        old_main = run("git", "rev-parse", f"{remote_main}^", cwd=self.origin).stdout.strip()
        run("jj", "edit", "--ignore-immutable", "@-", cwd=self.repo)
        run("jj", "bookmark", "set", "main", "--revision", old_main, "--allow-backwards", cwd=self.repo)

        check_only = self.release("--check", check=False)
        self.assertNotEqual(0, check_only.returncode)
        self.assertIn("rerun the exact release command", check_only.stderr)

        resumed = self.release()
        self.assertIn("Release plan (resume)", resumed.stdout)
        self.assertEqual("true", run("jj", "log", "-r", "@", "--no-graph", "-T", "empty", cwd=self.repo).stdout)
        self.assertEqual(remote_main, run("jj", "log", "-r", "@-", "--no-graph", "-T", "commit_id", cwd=self.repo).stdout)


if __name__ == "__main__":
    unittest.main()

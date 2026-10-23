#!/usr/bin/env python3
"""Back up all existing GitHub Actions artifact ZIPs to the artifacts branch, verify them, then delete their Actions copies.

Run only from the dedicated, authorized migration workflow. Never deletes an artifact
unless its exact ZIP bytes have been verified on the remote artifacts branch.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

BASE = "https://api.github.com"
PART_LIMIT = 40 * 1024 * 1024


def request(repo: str, token: str, endpoint: str, method: str = "GET"):
    req = urllib.request.Request(
        f"{BASE}/repos/{repo}/{endpoint}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Forever-artifact-migration",
        },
        method=method,
    )
    return urllib.request.urlopen(req, timeout=180)


def download_zip(repo: str, token: str, artifact_id: int, destination: Path):
    """Authenticate only to GitHub API; never forward its token to signed blob storage."""
    from urllib.parse import urlsplit

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    req = urllib.request.Request(
        f"{BASE}/repos/{repo}/actions/artifacts/{artifact_id}/zip",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Forever-artifact-migration",
        },
    )
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=60):
            raise RuntimeError("GitHub artifact download unexpectedly returned no redirect")
    except urllib.error.HTTPError as err:
        if err.code not in (302, 303, 307):
            raise
        location = err.headers.get("Location")
        if not location or urlsplit(location).scheme != "https":
            raise RuntimeError("GitHub returned an unsafe/missing artifact storage redirect") from None
    # The signed storage URL authorizes the download itself; adding GitHub's
    # bearer token here makes the blob service reject the request with HTTP 401.
    with urllib.request.urlopen(urllib.request.Request(location), timeout=180) as reply:
        with destination.open("wb") as out:
            while data := reply.read(1024 * 1024):
                out.write(data)


def inventory(repo: str, token: str) -> list[dict]:
    found = []
    page = 1
    while True:
        with request(repo, token, f"actions/artifacts?per_page=100&page={page}") as reply:
            batch = json.load(reply).get("artifacts", [])
        found.extend(batch)
        if len(batch) < 100:
            return found
        page += 1
        if page > 1000:
            raise RuntimeError("Artifact inventory exceeds 100,000 items; refusing partial cleanup")


def digest_file(path: Path):
    sha = hashlib.sha256()
    with path.open("rb") as fd:
        while block := fd.read(1024 * 1024):
            sha.update(block)
    return sha.hexdigest()


def git_blob_digest(workspace: Path, git_path: str):
    command = ["git", "-C", str(workspace), "show", f"refs/remotes/origin/artifacts:{git_path}"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    digest = hashlib.sha256()
    nbytes = 0
    assert process.stdout is not None
    with process.stdout:
        while part := process.stdout.read(1024 * 1024):
            digest.update(part)
            nbytes += len(part)
    error = process.stderr.read() if process.stderr else b""
    if process.wait() != 0:
        raise RuntimeError(f"Backup Git blob {git_path} missing: {error[:250]!r}")
    return digest.hexdigest(), nbytes


def git_blob_bytes(workspace: Path, git_path: str):
    return subprocess.check_output(
        ["git", "-C", str(workspace), "show", f"refs/remotes/origin/artifacts:{git_path}"]
    )


def verify_git_backup(workspace: Path, dest: str, local: Path):
    size = local.stat().st_size
    sha = digest_file(local)
    if size <= PART_LIMIT:
        got, got_size = git_blob_digest(workspace, dest)
        if got != sha or got_size != size:
            raise RuntimeError(f"Remote Git backup does not match {dest}")
        return
    metadata = json.loads(git_blob_bytes(workspace, dest + ".parts.json"))
    if metadata.get("size") != size or metadata.get("sha256") != sha or not metadata.get("parts"):
        raise RuntimeError(f"Invalid split backup metadata for {dest}")
    total_sha = hashlib.sha256()
    nbytes = 0
    for part in metadata["parts"]:
        # Each individually published part has a unique name and capped size.
        if not re.fullmatch(r"[^/]+\.part-\d{3,}", part):
            raise RuntimeError(f"Unsafe split artifact part name: {part!r}")
        path = str(Path(dest).parent / part)
        process = subprocess.Popen(
            ["git", "-C", str(workspace), "show", f"refs/remotes/origin/artifacts:{path}"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert process.stdout is not None
        with process.stdout:
            while block := process.stdout.read(1024 * 1024):
                total_sha.update(block)
                nbytes += len(block)
        error = process.stderr.read() if process.stderr else b""
        if process.wait() != 0:
            raise RuntimeError(f"Missing split backup part {path}: {error[:250]!r}")
    if nbytes != size or total_sha.hexdigest() != sha:
        raise RuntimeError(f"Reconstructed Git backup does not match {dest}")


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    token = os.environ["GH_TOKEN"]
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    artifacts = inventory(repo, token)
    print(f"Actions artifacts found: {len(artifacts)}", flush=True)
    if not artifacts:
        return
    # Expired artifacts cannot be downloaded, so never pretend to have preserved them.
    expired = [a for a in artifacts if a.get("expired")]
    if expired:
        print(f"{len(expired)} artifact(s) expired and cannot be backed up; leaving them untouched.", file=sys.stderr)
    active = [a for a in artifacts if not a.get("expired")]
    if not active:
        return

    with tempfile.TemporaryDirectory(prefix="old-action-artifacts-") as d:
        temp = Path(d)
        entries = []
        # Download and validate *all* before writing to Git or deleting anything.
        for artifact in active:
            id_ = int(artifact["id"])
            run_id = (artifact.get("workflow_run") or {}).get("id") or "unlinked"
            label = re.sub(r"[^A-Za-z0-9_.-]+", "-", artifact.get("name", "artifact"))[:80]
            filename = f"{id_}-{label}.zip"
            archive = temp / filename
            download_zip(repo, token, id_, archive)
            declared_size = artifact.get("size_in_bytes")
            if declared_size is not None and archive.stat().st_size != declared_size:
                raise RuntimeError(f"Artifact {id_} ZIP size mismatches GitHub metadata")
            with zipfile.ZipFile(archive, "r") as zf:
                corrupt = zf.testzip()
                if corrupt:
                    raise RuntimeError(f"Artifact {id_} ZIP member {corrupt} failed CRC")
            dest = f"legacy-actions/runs/{run_id}/{filename}"
            entries.append((id_, archive, dest))
            print(f"Downloaded and validated {id_}: {archive.stat().st_size} bytes", flush=True)

        subprocess.run(
            ["bash", ".github/scripts/publish-artifacts.sh", *[f"{p}::{dest}" for _, p, dest in entries]],
            cwd=workspace, check=True,
        )
        # Verify bytes from the branch fetched again from origin, not just the local worktree.
        subprocess.run(
            ["git", "-C", str(workspace), "fetch", "--no-tags", "origin",
             "+refs/heads/artifacts:refs/remotes/origin/artifacts"],
            check=True,
        )
        for id_, archive, dest in entries:
            verify_git_backup(workspace, dest, archive)
            print(f"Verified remote backup for artifact {id_}: {dest}", flush=True)

        errors = []
        for id_, _, dest in entries:
            try:
                with request(repo, token, f"actions/artifacts/{id_}", method="DELETE") as response:
                    if response.status != 204:
                        raise RuntimeError(f"GitHub DELETE returned HTTP {response.status}")
                print(f"Removed old Actions artifact {id_}; protected copy: {dest}", flush=True)
            except (urllib.error.HTTPError, urllib.error.URLError, RuntimeError) as exc:
                errors.append((id_, str(exc)))
        if errors:
            raise RuntimeError(f"Could not remove {len(errors)} safely copied Actions artifacts: {errors}")


if __name__ == "__main__":
    main()

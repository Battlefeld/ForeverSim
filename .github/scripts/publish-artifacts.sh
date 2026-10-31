#!/usr/bin/env bash
# Store generated workflow outputs on the independent 'artifacts' branch.
# Usage: bash .github/scripts/publish-artifacts.sh source::destination [source::destination ...]
# Large files are split into 40 MiB Git-safe parts + a SHA-256 manifest.
set -euo pipefail
: "${GITHUB_WORKSPACE:?Must run from a GitHub Actions checkout}"
: "${RUNNER_TEMP:?Must run on a GitHub Actions runner}"
if (( $# == 0 )); then
  echo "Expected at least one source::destination mapping" >&2
  exit 2
fi
workspace="$GITHUB_WORKSPACE"
tempdir="$(mktemp -d "$RUNNER_TEMP/generated-artifacts.XXXXXX")"
worktree="$tempdir/branch"
cleanup() {
  git -C "$workspace" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$tempdir"
}
trap cleanup EXIT
if git -C "$workspace" fetch -q --no-tags origin +refs/heads/artifacts:refs/remotes/origin/artifacts; then
  git -C "$workspace" worktree add -q --detach "$worktree" refs/remotes/origin/artifacts
else
  # no artifacts branch yet (first run, or it was deleted): start an empty one
  git -C "$workspace" worktree add -q --detach "$worktree" HEAD
  git -C "$worktree" checkout -q --orphan artifacts
  git -C "$worktree" rm -rfq . >/dev/null 2>&1 || true
  git -C "$worktree" clean -fdxq
fi
python - "$worktree" "$@" <<'PY'
from pathlib import Path
import hashlib
import json
import shutil
import sys

root = Path(sys.argv[1]).resolve()
limit = 40 * 1024 * 1024
for mapping in sys.argv[2:]:
    if "::" not in mapping:
        raise SystemExit(f"Invalid source::destination mapping: {mapping!r}")
    source_name, destination = mapping.split("::", 1)
    src = Path(source_name).resolve()
    rel = Path(destination)
    if not src.is_file():
        raise SystemExit(f"Artifact missing: {src}")
    if rel.is_absolute() or not rel.parts or any(p in (".", "..") for p in rel.parts):
        raise SystemExit(f"Unsafe artifact path: {destination!r}")
    dst = root / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.unlink(missing_ok=True)
    (dst.parent / (dst.name + ".parts.json")).unlink(missing_ok=True)
    for stale in dst.parent.glob(dst.name + ".part-*"):
        if stale.is_file():
            stale.unlink()
    if src.stat().st_size <= limit:
        shutil.copyfile(src, dst)
        print(f"Saved {rel} ({src.stat().st_size} bytes)")
        continue
    pieces = []
    digest = hashlib.sha256()
    with src.open("rb") as incoming:
        index = 0
        while block := incoming.read(limit):
            digest.update(block)
            part = f"{dst.name}.part-{index:03d}"
            (dst.parent / part).write_bytes(block)
            pieces.append(part)
            index += 1
    manifest = {"format": "git-parts-v1", "original_name": dst.name,
                "size": src.stat().st_size, "sha256": digest.hexdigest(),
                "parts": pieces}
    (dst.parent / (dst.name + ".parts.json")).write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {rel} as {len(pieces)} Git-safe parts; SHA-256: {digest.hexdigest()}")
PY

git -C "$worktree" config user.name "github-actions[bot]"
git -C "$worktree" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$worktree" add -A
if git -C "$worktree" diff --cached --quiet; then
  echo "Artifact contents unchanged"
  exit 0
fi
git -C "$worktree" commit -q -m "artifacts: ${GITHUB_WORKFLOW:-workflow} run ${GITHUB_RUN_ID:-manual}"
for attempt in 1 2 3 4 5; do
  if git -C "$worktree" push -q origin HEAD:refs/heads/artifacts; then
    echo "Saved generated outputs to $GITHUB_REPOSITORY / artifacts"
    exit 0
  fi
  echo "Artifact branch advanced; rebasing before retry $attempt" >&2
  if git -C "$workspace" fetch -q --no-tags origin +refs/heads/artifacts:refs/remotes/origin/artifacts; then
    git -C "$worktree" rebase -q -X theirs refs/remotes/origin/artifacts
  fi
done
echo "Cannot publish to artifacts after five retries" >&2
exit 1

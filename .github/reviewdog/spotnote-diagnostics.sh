#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
import re
import subprocess
from pathlib import Path

REPO = Path.cwd()
TRIGGER = "REVIEWDOG_DIAGNOSTIC_TRIGGER"
SELF = ".github/reviewdog/spotnote-diagnostics.sh"
WORKFLOW_RE = re.compile(r"^\.github/workflows/.*\.ya?ml$")
USES_RE = re.compile(r"^\s*-?\s*uses:\s*([^\s#]+)")
PINNED_SHA_RE = re.compile(r"@[0-9a-fA-F]{40}$")
ROLE_CONFLICT_RE = re.compile(r"\b(?:Danger|Reviewdog)\b.*\bsemantic reviewer\b", re.IGNORECASE)
RUNTIME_PATH_PREFIXES = ("Sources/", "Tests/", "scripts/", "Tools/", "App/")


def run_git(args):
    result = subprocess.run(
        ["git", *args],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def git_commit_exists(ref):
    if not ref:
        return False
    return subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        cwd=REPO,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def read_event():
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return {}
    try:
        return json.loads(Path(event_path).read_text())
    except Exception:
        return {}


def changed_files():
    override = os.environ.get("SPOTNOTE_REVIEWDOG_CHANGED_FILES")
    if override:
        return [part.strip() for part in re.split(r"[\n,]", override) if part.strip()]

    event = read_event()
    pr = event.get("pull_request") or {}
    base = ((pr.get("base") or {}).get("sha") or "").strip()
    head = ((pr.get("head") or {}).get("sha") or "").strip()
    if git_commit_exists(base) and git_commit_exists(head):
        return [line for line in run_git(["diff", "--name-only", f"{base}...{head}"]).splitlines() if line]

    if git_commit_exists("HEAD~1"):
        return [line for line in run_git(["diff", "--name-only", "HEAD~1...HEAD"]).splitlines() if line]

    return []


def emit(path, line, message):
    print(f"{path}:{line}:1: {message}")


def action_ref_is_pinned(ref):
    if ref.startswith("./") or ref.startswith("docker://"):
        return True
    return bool(PINNED_SHA_RE.search(ref))


def check_workflow(path):
    file_path = REPO / path
    if not file_path.exists():
        return
    lines = file_path.read_text(errors="replace").splitlines()
    job_lines = [i for i, line in enumerate(lines, start=1) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", line)]
    if job_lines and not any("timeout-minutes:" in line for line in lines):
        emit(path, 1, "workflow should set timeout-minutes on jobs so stuck checks fail closed")
    for index, line in enumerate(lines, start=1):
        match = USES_RE.search(line)
        if not match:
            continue
        ref = match.group(1)
        if not action_ref_is_pinned(ref):
            emit(path, index, f"GitHub Action `{ref}` is not pinned to a full commit SHA")


def check_trigger_marker(path):
    if path == SELF:
        return
    file_path = REPO / path
    if not file_path.exists() or not file_path.is_file():
        return
    try:
        for index, line in enumerate(file_path.read_text(errors="replace").splitlines(), start=1):
            if TRIGGER in line:
                emit(path, index, "reviewdog diagnostic trigger marker found; remove before merging")
    except OSError:
        return


def check_role_language(path):
    if path not in {"REVIEW.md", ".cursor/BUGBOT.md", ".cursor/rules/pr-flow.mdc"}:
        return
    file_path = REPO / path
    if not file_path.exists():
        return
    for index, line in enumerate(file_path.read_text(errors="replace").splitlines(), start=1):
        if ROLE_CONFLICT_RE.search(line):
            emit(path, index, "Reviewdog/Danger should be deterministic advisory automation, not semantic reviewers")


def check_runtime_path(path):
    if path.startswith(RUNTIME_PATH_PREFIXES) or path in {"Package.swift", "project.yml"}:
        if path == SELF:
            return
        file_path = REPO / path
        if file_path.exists() and file_path.is_file():
            for index, line in enumerate(file_path.read_text(errors="replace").splitlines(), start=1):
                if "swiftlint:disable" in line and "justification" not in line.lower():
                    emit(path, index, "swiftlint disables should carry an inline justification")


def smoke_marker_diagnostic():
    event = read_event()
    title = (((event.get("pull_request") or {}).get("title")) or "")
    head_ref = os.environ.get("GITHUB_HEAD_REF", "")
    if "[reviewdog-smoke]" in title or "review-annotations-smoke" in head_ref:
        emit(".github/workflows/review-annotations.yml", 1, "reviewdog diagnostic smoke marker active; advisory check path is live")


files = changed_files()
for path in files:
    if WORKFLOW_RE.match(path):
        check_workflow(path)
    check_trigger_marker(path)
    check_role_language(path)
    check_runtime_path(path)
smoke_marker_diagnostic()
PY

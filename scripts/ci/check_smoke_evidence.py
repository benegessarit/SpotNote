#!/usr/bin/env python3
"""Require professional smoke evidence on PRs that touch runnable SpotNote surfaces.

A passing PR body includes either:

- `Smoke:` plus setup/result/cleanup details; or
- `Smoke: not run ...` plus a reason and substitute/adjacent proof.

The check validates evidence shape only. It does not judge whether the smoke is sufficient.
That judgment stays with humans, Bugbot, and repo-specific review instructions.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
SMOKE_RE = re.compile(r"(?im)^\s*(?:[-*+]\s*)?Smoke\s*:")
NO_SMOKE_RE = re.compile(r"(?i)\b(not run|not possible|impossible|unsafe|skipped)\b")
PLACEHOLDER_VALUE_RE = re.compile(
    r"(?i)"
    r"\b(?:setup|result|cleanup|reason|substitute|adjacent)\b\s*[:=]\s*"
    r"(?:<[^>\n]+>|\.\.\.|todo\b|tbd\b|placeholder\b|fill\s+in\b)"
)


class ChangedFilesError(RuntimeError):
    pass


class EventReadError(RuntimeError):
    pass


def run_git(args: list[str], *, cwd: Path) -> str:
    proc = subprocess.run(["git", *args], cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "git command failed").strip()
        raise ChangedFilesError(f"git {' '.join(args)} failed: {detail}")
    return proc.stdout


def read_event(path: Path | None) -> dict:
    if not path:
        return {}
    if not path.exists():
        raise EventReadError(f"event file does not exist: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise EventReadError(f"could not parse event JSON at {path}: {exc}") from exc


def changed_files(repo_root: Path, event: dict, explicit_file: Path | None) -> list[str]:
    if explicit_file:
        if not explicit_file.exists():
            raise ChangedFilesError(f"changed-files list does not exist: {explicit_file}")
        return [line.strip() for line in explicit_file.read_text(encoding="utf-8").splitlines() if line.strip()]

    pr = event.get("pull_request") if isinstance(event, dict) else None
    if isinstance(pr, dict):
        base_sha = ((pr.get("base") or {}).get("sha") or "").strip()
        head_sha = ((pr.get("head") or {}).get("sha") or "").strip()
        if base_sha and head_sha:
            out = run_git(["diff", "--name-only", f"{base_sha}...{head_sha}"], cwd=repo_root)
            if out:
                return [line.strip() for line in out.splitlines() if line.strip()]

    out = run_git(["diff", "--name-only", "HEAD~1...HEAD"], cwd=repo_root)
    return [line.strip() for line in out.splitlines() if line.strip()]


def pr_body(event: dict) -> str:
    pr = event.get("pull_request") if isinstance(event, dict) else None
    if not isinstance(pr, dict):
        return ""
    return str(pr.get("body") or "")


def is_doc_only(path: str) -> bool:
    if path.endswith((".md", ".txt")):
        return True
    if path.startswith("docs/"):
        return True
    return False


def needs_smoke(path: str) -> bool:
    if path in {"Package.swift", "Makefile", "project.yml"}:
        return True
    if path.startswith(("Sources/", "Tests/", "scripts/", "App/", ".github/workflows/", ".cursor/")):
        return True
    if path.endswith((".py", ".sh", ".js", ".cjs", ".ts", ".json", ".yml", ".yaml")) and not is_doc_only(path):
        return True
    return False


def visible_body(body: str) -> str:
    """Remove Markdown comments so hidden template examples cannot satisfy the gate."""
    return HTML_COMMENT_RE.sub("", body)


def smoke_lines(body: str) -> list[str]:
    return [line.strip() for line in visible_body(body).splitlines() if SMOKE_RE.match(line)]


def has_labeled_value(line: str, label: str) -> bool:
    return re.search(rf"\b{re.escape(label)}\b\s*[:=]\s*[^;\s]", line, re.IGNORECASE) is not None


def professional_smoke_evidence(body: str) -> tuple[bool, str]:
    lines = smoke_lines(body)
    if not lines:
        return False, "missing `Smoke:` evidence block"

    placeholder_seen = False
    fallback_reason = "`Smoke:` evidence must mention setup, result, and cleanup"
    for line in lines:
        if PLACEHOLDER_VALUE_RE.search(line):
            placeholder_seen = True
            continue

        lower = line.lower()
        if not lower.partition(":")[2].strip():
            fallback_reason = "`Smoke:` evidence is empty; fill in setup/result/cleanup or a no-smoke reason/substitute"
            continue

        missing = [word for word in ("setup", "result", "cleanup") if not has_labeled_value(line, word)]
        if not missing:
            return True, "smoke evidence includes setup/result/cleanup"

        if NO_SMOKE_RE.search(line):
            has_reason = has_labeled_value(line, "reason")
            has_substitute = has_labeled_value(line, "substitute") or has_labeled_value(line, "adjacent")
            if has_reason and has_substitute:
                return True, "no-smoke exception includes reason and substitute proof"
            fallback_reason = "no-smoke exception needs reason and substitute/adjacent proof"
            continue

        fallback_reason = f"`Smoke:` evidence missing label(s): {', '.join(missing)}"

    if placeholder_seen:
        return False, "`Smoke:` evidence still contains template placeholders"

    return False, fallback_reason


def github_error(message: str) -> None:
    safe = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error title=Smoke evidence required::{safe}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check PR body smoke evidence for changed runnable surfaces")
    parser.add_argument("--repo-root", default=".", help="repository root")
    parser.add_argument("--event-path", default=None, help="GitHub event JSON path; defaults to GITHUB_EVENT_PATH when set")
    parser.add_argument("--changed-files", default=None, help="optional newline-separated changed-files list")
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    event_path = Path(args.event_path).resolve() if args.event_path else None
    if event_path is None:
        import os

        raw = os.environ.get("GITHUB_EVENT_PATH")
        event_path = Path(raw).resolve() if raw else None

    try:
        event = read_event(event_path)
    except EventReadError as exc:
        message = f"Could not read the pull request event, so the smoke evidence gate fails closed: {exc}"
        github_error(message)
        print("FAIL " + message, file=sys.stderr)
        return 1

    try:
        files = changed_files(repo_root, event, Path(args.changed_files).resolve() if args.changed_files else None)
    except ChangedFilesError as exc:
        message = f"Could not determine changed files, so the smoke evidence gate fails closed: {exc}"
        github_error(message)
        print("FAIL " + message, file=sys.stderr)
        return 1

    relevant = [f for f in files if needs_smoke(f)]
    if not relevant:
        print(f"smoke evidence: ok; no smoke-relevant files among {len(files)} changed file(s)")
        return 0

    ok, reason = professional_smoke_evidence(pr_body(event))
    if ok:
        print(f"smoke evidence: ok; {len(relevant)} smoke-relevant file(s); {reason}")
        return 0

    preview = ", ".join(relevant[:10])
    if len(relevant) > 10:
        preview += f", ... +{len(relevant) - 10} more"
    message = (
        f"{reason}. Changed smoke-relevant files: {preview}. Add `Smoke: setup=...; result=...; cleanup=...` "
        "to the PR description, or `Smoke: not run — reason=...; substitute=...` when a real smoke is impossible/unsafe."
    )
    github_error(message)
    print("FAIL " + message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

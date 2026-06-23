#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check_smoke_evidence.py")
spec = importlib.util.spec_from_file_location("check_smoke_evidence", MODULE_PATH)
assert spec and spec.loader
check_smoke_evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_smoke_evidence)


class SmokeEvidenceShapeTests(unittest.TestCase):
    def assert_ok(self, body: str) -> str:
        ok, reason = check_smoke_evidence.professional_smoke_evidence(body)
        self.assertTrue(ok, reason)
        return reason

    def assert_not_ok(self, body: str) -> str:
        ok, reason = check_smoke_evidence.professional_smoke_evidence(body)
        self.assertFalse(ok, reason)
        return reason

    def test_untouched_template_fails(self) -> None:
        body = """## Verification
- Local checks:
- Smoke:

<!-- Fill the Smoke line above as either:
setup=<temp fixture>; result=<observed pass signal>; cleanup=<removed temp files>.
-->
"""
        self.assertIn("empty", self.assert_not_ok(body))

    def test_markdown_bullet_form_passes(self) -> None:
        reason = self.assert_ok("- Smoke: setup=temp fixture; result=checker failed as expected; cleanup=temp files removed")
        self.assertIn("setup/result/cleanup", reason)

    def test_placeholder_evidence_fails(self) -> None:
        self.assertIn(
            "placeholder",
            self.assert_not_ok("Smoke: setup=<temp>; result=<pass>; cleanup=<removed>"),
        )
        self.assertIn(
            "placeholder",
            self.assert_not_ok("Smoke: setup=...; result=passed; cleanup=removed"),
        )
        self.assertIn(
            "placeholder",
            self.assert_not_ok("Smoke: setup=todo; result=passed; cleanup=removed"),
        )

    def test_literal_domain_terms_in_concrete_value_are_allowed(self) -> None:
        self.assert_ok("Smoke: setup=temp /todo route fixture; result=passed with truncated output...; cleanup=removed")

    def test_concrete_smoke_beats_no_smoke_trigger_words(self) -> None:
        self.assert_ok(
            "Smoke: setup=unsafe-word fixture; result=not run phrase handled by test; cleanup=removed temp files"
        )

    def test_unrelated_body_text_cannot_create_no_smoke_exception(self) -> None:
        body = """Smoke: setup=temp fixture; result=passed; cleanup=removed

## Not covered
- external API not run
"""
        self.assert_ok(body)

    def test_no_smoke_exception_requires_reason_and_substitute(self) -> None:
        self.assert_ok("Smoke: not run — reason=config-only change; substitute=py_compile and actionlint")
        self.assertIn("reason", self.assert_not_ok("Smoke: not run — substitute=py_compile"))
        self.assertIn("substitute", self.assert_not_ok("Smoke: not run — reason=unsafe external write"))
        self.assertIn("reason", self.assert_not_ok("Smoke: not run because unsafe; instead py_compile"))

    def test_fields_need_labeled_values(self) -> None:
        reason = self.assert_not_ok("Smoke: setup=; result=passed; cleanup=removed")
        self.assertIn("setup", reason)

    def test_hidden_comment_examples_are_ignored(self) -> None:
        body = """<!-- Smoke: setup=temp; result=passed; cleanup=removed -->
No visible smoke evidence.
"""
        self.assertIn("missing", self.assert_not_ok(body))

    def test_needs_smoke_scope(self) -> None:
        self.assertTrue(check_smoke_evidence.needs_smoke("Sources/Spotlight/App.swift"))
        self.assertTrue(check_smoke_evidence.needs_smoke("App/Info.plist"))
        self.assertTrue(check_smoke_evidence.needs_smoke(".github/workflows/repo-quality.yml"))
        self.assertTrue(check_smoke_evidence.needs_smoke("scripts/ci/check_smoke_evidence.py"))
        self.assertFalse(check_smoke_evidence.needs_smoke("README.md"))
        self.assertFalse(check_smoke_evidence.needs_smoke("docs/architecture.md"))


class SmokeEvidenceCliTests(unittest.TestCase):
    def run_checker(self, body: str, changed_files: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            event = root / "event.json"
            files = root / "changed.txt"
            event.write_text(json.dumps({"pull_request": {"body": body}}), encoding="utf-8")
            files.write_text(changed_files, encoding="utf-8")
            return subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    "--repo-root",
                    str(root),
                    "--event-path",
                    str(event),
                    "--changed-files",
                    str(files),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

    def test_cli_fails_only_for_relevant_changes_without_valid_smoke(self) -> None:
        docs_only = self.run_checker("", "README.md\ndocs/notes.md\n")
        self.assertEqual(docs_only.returncode, 0, docs_only.stderr)

        runnable_missing = self.run_checker("", "Sources/Spotlight/App.swift\n")
        self.assertEqual(runnable_missing.returncode, 1, runnable_missing.stdout)
        self.assertIn("Smoke evidence required", runnable_missing.stdout)

        runnable_valid = self.run_checker(
            "Smoke: setup=temp app build; result=make build passed; cleanup=no persistent state created",
            "Sources/Spotlight/App.swift\n",
        )
        self.assertEqual(runnable_valid.returncode, 0, runnable_valid.stderr)

    def test_cli_fails_closed_when_changed_files_cannot_be_determined(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            event = root / "event.json"
            event.write_text(
                json.dumps(
                    {
                        "pull_request": {
                            "body": "",
                            "base": {"sha": "bad-base"},
                            "head": {"sha": "bad-head"},
                        }
                    }
                ),
                encoding="utf-8",
            )
            proc = subprocess.run(
                [sys.executable, str(MODULE_PATH), "--repo-root", str(root), "--event-path", str(event)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(proc.returncode, 1, proc.stdout)
            self.assertIn("fails closed", proc.stderr)

    def test_cli_fails_closed_when_event_json_is_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            event = root / "event.json"
            files = root / "changed.txt"
            event.write_text("{not json", encoding="utf-8")
            files.write_text("Sources/Spotlight/App.swift\n", encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    "--repo-root",
                    str(root),
                    "--event-path",
                    str(event),
                    "--changed-files",
                    str(files),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(proc.returncode, 1, proc.stdout)
            self.assertIn("fails closed", proc.stderr)

    def test_cli_fails_closed_when_explicit_changed_files_list_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            event = root / "event.json"
            missing = root / "missing.txt"
            event.write_text(json.dumps({"pull_request": {"body": ""}}), encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    "--repo-root",
                    str(root),
                    "--event-path",
                    str(event),
                    "--changed-files",
                    str(missing),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(proc.returncode, 1, proc.stdout)
            self.assertIn("fails closed", proc.stderr)


if __name__ == "__main__":
    unittest.main()

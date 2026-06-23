#!/usr/bin/env node
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "../..");
const { runSpotNoteDanger, smokeEvidence } = require(path.join(repoRoot, "Dangerfile.js"));
const pinnedCheckout = "de0fac2e4500dabe0009e67214ff5f5447ce83dd";
const triggerMarker = ["REVIEWDOG", "DIAGNOSTIC", "TRIGGER"].join("_");

function dangerFixture(overrides = {}) {
  return {
    github: {
      pr: {
        title: "Clean PR",
        body: "Smoke: setup=temp fixture; result=passed; cleanup=removed temp fixture.",
        additions: 12,
        deletions: 3,
        number: 1,
        user: { login: "smoke-test" },
        ...(overrides.pr || {}),
      },
    },
    git: {
      modified_files: [],
      created_files: [],
      deleted_files: [],
      ...(overrides.git || {}),
    },
  };
}

function runDanger(danger) {
  const calls = { warn: [], message: [], markdown: [] };
  const result = runSpotNoteDanger({
    danger,
    warn: (text) => calls.warn.push(String(text)),
    message: (text) => calls.message.push(String(text)),
    markdown: (text) => calls.markdown.push(String(text)),
  });
  return { calls, result };
}

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    ...options,
  });
  assert.strictEqual(
    result.status,
    0,
    `${command} ${args.join(" ")} failed; stdout=${result.stdout}; stderr=${result.stderr}`
  );
  return result.stdout.trim();
}

function commitAll(cwd, message) {
  runCommand("git", ["add", "."], { cwd });
  runCommand("git", ["commit", "-m", message], { cwd });
  return runCommand("git", ["rev-parse", "HEAD"], { cwd });
}

function createTempDiagnosticsRepo() {
  const tmpRepo = fs.mkdtempSync(path.join(os.tmpdir(), "spotnote-reviewdog-smoke-"));
  const scriptPath = path.join(tmpRepo, ".github/reviewdog/spotnote-diagnostics.sh");
  fs.mkdirSync(path.dirname(scriptPath), { recursive: true });
  fs.copyFileSync(path.join(repoRoot, ".github/reviewdog/spotnote-diagnostics.sh"), scriptPath);
  fs.chmodSync(scriptPath, 0o755);

  runCommand("git", ["init"], { cwd: tmpRepo });
  runCommand("git", ["config", "user.email", "reviewdog-smoke@example.invalid"], { cwd: tmpRepo });
  runCommand("git", ["config", "user.name", "Reviewdog Smoke"], { cwd: tmpRepo });
  runCommand("git", ["config", "commit.gpgsign", "false"], { cwd: tmpRepo });
  const baseSha = commitAll(tmpRepo, "base diagnostics");
  return { tmpRepo, scriptPath, baseSha };
}

function runDiagnostics({ tmpRepo, scriptPath, baseSha, headSha, title = "Diagnostics fixture", headRef = "feature/review-annotations-smoke" }) {
  const eventPath = path.join(tmpRepo, "event.json");
  fs.writeFileSync(
    eventPath,
    JSON.stringify({
      pull_request: {
        title,
        base: { sha: baseSha },
        head: { sha: headSha },
      },
    })
  );
  const result = spawnSync("bash", [scriptPath], {
    cwd: tmpRepo,
    env: {
      ...process.env,
      GITHUB_EVENT_PATH: eventPath,
      GITHUB_HEAD_REF: headRef,
    },
    encoding: "utf8",
  });
  fs.rmSync(eventPath, { force: true });
  return result;
}

{
  assert.deepStrictEqual(
    smokeEvidence("Smoke: setup=temp; result=passed; cleanup=removed."),
    { ok: true, placeholder: false, noSmoke: false },
    "professional smoke line should parse"
  );
  assert.strictEqual(
    smokeEvidence("Smoke: setup=<temp>; result=<pass>; cleanup=<none>").placeholder,
    true,
    "template smoke line should be treated as placeholder"
  );
}

{
  const smokeChecker = spawnSync("python3", [path.join(repoRoot, "scripts/ci/test_check_smoke_evidence.py")], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.strictEqual(
    smokeChecker.status,
    0,
    `smoke evidence checker tests failed; stdout=${smokeChecker.stdout}; stderr=${smokeChecker.stderr}`
  );
}

{
  const { calls } = runDanger(dangerFixture());
  assert.deepStrictEqual(calls.warn, [], "clean fixture with smoke evidence should not warn");
  assert.deepStrictEqual(calls.message, [], "clean fixture should stay quiet");
}

{
  const { calls } = runDanger(
    dangerFixture({
      pr: { body: "" },
      git: { modified_files: ["Sources/Spotlight/SpotlightRootView.swift"] },
    })
  );
  assert(
    calls.warn.some((text) => text.includes("Swift source changed")),
    "Danger should warn when Swift source changes have no tests or smoke/no-test rationale"
  );
}

{
  const { calls } = runDanger(
    dangerFixture({
      pr: { body: "" },
      git: {
        modified_files: [
          "Sources/Spotlight/SpotlightRootView.swift",
          "Tests/SpotlightTests/SpotlightRootViewVisualStyleTests.swift",
        ],
      },
    })
  );
  assert(
    !calls.warn.some((text) => text.includes("Swift source changed")),
    "Danger should not warn when Swift source changes include tests"
  );
}

{
  const { calls } = runDanger(
    dangerFixture({
      pr: { body: "Smoke: setup=<temp>; result=<pass>; cleanup=<none>" },
      git: { modified_files: ["Sources/Spotlight/MultilineEditor.swift"] },
    })
  );
  assert(
    calls.warn.some((text) => text.includes("template placeholder")),
    "Danger should flag placeholder smoke evidence"
  );
}

{
  const { calls } = runDanger(
    dangerFixture({
      pr: { body: "" },
      git: { modified_files: ["Sources/Spotlight/MultilineEditorVim.swift"] },
    })
  );
  assert(
    calls.warn.some((text) => text.includes("HUD/editor/install/launch behavior")),
    "Danger should warn when HUD/editor paths have no smoke evidence"
  );
}

{
  const { calls } = runDanger(dangerFixture({ pr: { additions: 450, deletions: 125 } }));
  assert(calls.warn.some((text) => text.includes("Large PR")), "Danger should warn on large PRs");
}

{
  const { calls } = runDanger(
    dangerFixture({
      git: { modified_files: [".github/workflows/review-annotations.yml"] },
    })
  );
  assert(
    calls.message.some((text) => text.includes("Review automation changed")),
    "Danger should message when review automation changes"
  );
}

{
  const { tmpRepo, scriptPath, baseSha } = createTempDiagnosticsRepo();
  try {
    const workflowPath = path.join(tmpRepo, ".github/workflows/trigger-fixture.yml");
    fs.mkdirSync(path.dirname(workflowPath), { recursive: true });
    fs.writeFileSync(
      workflowPath,
      [
        "name: trigger fixture",
        "on: pull_request",
        "jobs:",
        "  test:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - uses: actions/checkout@v6",
        "      - run: echo ok",
        `# ${triggerMarker}`,
        "",
      ].join("\n")
    );
    const reviewPath = path.join(tmpRepo, "REVIEW.md");
    fs.writeFileSync(reviewPath, "Danger is a semantic reviewer.\n");
    const sourcePath = path.join(tmpRepo, "Sources/Spotlight/Fixture.swift");
    fs.mkdirSync(path.dirname(sourcePath), { recursive: true });
    fs.writeFileSync(sourcePath, "// swiftlint:disable force_unwrapping\n");
    const headSha = commitAll(tmpRepo, "add trigger workflow fixture");
    const result = runDiagnostics({ tmpRepo, scriptPath, baseSha, headSha });
    assert.strictEqual(result.status, 0, `diagnostics should exit 0; stderr=${result.stderr}`);
    assert.match(result.stdout, /workflow should set timeout-minutes/, "diagnostics should flag missing timeout");
    assert.match(result.stdout, /actions\/checkout@v6.*not pinned/, "diagnostics should flag unpinned actions");
    assert.match(result.stdout, /reviewdog diagnostic trigger marker found/, "diagnostics should flag trigger markers");
    assert.match(result.stdout, /deterministic advisory automation/, "diagnostics should flag role-language conflicts");
    assert.match(result.stdout, /swiftlint disables should carry/, "diagnostics should flag unjustified swiftlint disables");
  } finally {
    fs.rmSync(tmpRepo, { recursive: true, force: true });
  }
}

{
  const { tmpRepo, scriptPath, baseSha } = createTempDiagnosticsRepo();
  try {
    const workflowPath = path.join(tmpRepo, ".github/workflows/clean-fixture.yml");
    fs.mkdirSync(path.dirname(workflowPath), { recursive: true });
    fs.writeFileSync(
      workflowPath,
      [
        "name: clean fixture",
        "on: pull_request",
        "jobs:",
        "  test:",
        "    runs-on: ubuntu-latest",
        "    timeout-minutes: 5",
        "    steps:",
        `      - uses: actions/checkout@${pinnedCheckout}`,
        "      - run: echo ok",
        "",
      ].join("\n")
    );
    const headSha = commitAll(tmpRepo, "add clean workflow fixture");
    const result = runDiagnostics({
      tmpRepo,
      scriptPath,
      baseSha,
      headSha,
      title: "Clean fixture",
      headRef: "feature/clean-fixture",
    });
    assert.strictEqual(result.status, 0, `diagnostics should exit 0 for clean fixture; stderr=${result.stderr}`);
    assert.strictEqual(result.stdout.trim(), "", "clean fixture should not emit diagnostics");
  } finally {
    fs.rmSync(tmpRepo, { recursive: true, force: true });
  }
}

console.log("review automation smoke ok");

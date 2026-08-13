function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function changedFiles(git = {}) {
  return unique([
    ...(git.modified_files || []),
    ...(git.created_files || []),
    ...(git.deleted_files || []),
  ]);
}

function isSwiftSource(file) {
  return file.startsWith("Sources/") && file.endsWith(".swift");
}

function isSwiftTest(file) {
  return file.startsWith("Tests/") && file.endsWith(".swift");
}

function isAppRuntimePath(file) {
  return (
    file.startsWith("Sources/") ||
    file.startsWith("App/") ||
    file === "Package.swift" ||
    file === "project.yml" ||
    file.startsWith("scripts/") ||
    file.startsWith("Tools/")
  );
}

function isHudEditorOrInstallPath(file) {
  const lower = file.toLowerCase();
  return (
    lower.includes("spotlight") ||
    lower.includes("editor") ||
    lower.includes("vim") ||
    lower.includes("hud") ||
    lower.includes("hotkey") ||
    lower.includes("handoff") ||
    lower.includes("install") ||
    lower.includes("launch") ||
    lower.includes("headless")
  );
}

function isReviewAutomationPath(file) {
  return (
    file === "Dangerfile.js" ||
    file.startsWith(".github/workflows/") ||
    file.startsWith(".github/reviewdog/") ||
    file === ".github/scripts/smoke-review-automation.cjs" ||
    file.startsWith("scripts/ci/") ||
    file === "REVIEW.md" ||
    file.startsWith(".cursor/") ||
    file === ".pre-commit-config.yaml"
  );
}

const SMOKE_LINE_RE = /^\s*Smoke\s*:/i;
const PLACEHOLDER_RE = /<[^>]+>|\.\.\.|setup\s*[:=]\s*(?:<|\.\.\.)|result\s*[:=]\s*(?:<|\.\.\.)|cleanup\s*[:=]\s*(?:<|\.\.\.)/i;
const NO_SMOKE_RE = /not\s+run|no[- ]smoke|unsafe|impossible|skipped/i;

function visibleBody(body = "") {
  return String(body).replace(/<!--([\s\S]*?)-->/g, "");
}

function smokeLines(body = "") {
  return visibleBody(body)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => SMOKE_LINE_RE.test(line));
}

function hasLabeledValue(line, label) {
  return new RegExp(`\\b${label}\\b\\s*[:=]\\s*[^;\\s]`, "i").test(line);
}

function smokeEvidence(body = "") {
  const lines = smokeLines(body);
  let placeholder = false;

  for (const line of lines) {
    if (PLACEHOLDER_RE.test(line)) {
      placeholder = true;
      continue;
    }

    const hasSetup = hasLabeledValue(line, "setup");
    const hasResult = hasLabeledValue(line, "result");
    const hasCleanup = hasLabeledValue(line, "cleanup");
    if (hasSetup && hasResult && hasCleanup) {
      return { ok: true, placeholder: false, noSmoke: false };
    }

    const hasReason = hasLabeledValue(line, "reason");
    const hasSubstitute = hasLabeledValue(line, "substitute") || hasLabeledValue(line, "adjacent");
    if (NO_SMOKE_RE.test(line) && hasReason && hasSubstitute) {
      return { ok: true, placeholder: false, noSmoke: true };
    }
  }

  return { ok: false, placeholder, noSmoke: false };
}

function bodyHasNoTestRationale(body = "") {
  const text = visibleBody(body).toLowerCase();
  return /no[- ]tests?|tests? not useful|covered by smoke|manual smoke|substitute proof/.test(text);
}

function runSpotNoteDanger(api = {}) {
  const dangerApi = api.danger || globalThis.danger;
  if (!dangerApi) {
    throw new Error("Danger DSL is unavailable");
  }

  const warnFn = api.warn || globalThis.warn || (() => {});
  const messageFn = api.message || globalThis.message || (() => {});
  const markdownFn = api.markdown || globalThis.markdown || (() => {});

  const pr = (dangerApi.github && dangerApi.github.pr) || {};
  const body = pr.body || "";
  const files = changedFiles(dangerApi.git || {});
  const title = pr.title || "";
  const headRef = process.env.GITHUB_HEAD_REF || "";
  const isSmoke = /\[(danger|reviewdog)-smoke\]/i.test(title) || /review-annotations-smoke/.test(headRef);
  const smoke = smokeEvidence(body);

  const swiftSourceChanged = files.some(isSwiftSource);
  const swiftTestsChanged = files.some(isSwiftTest);
  const appRuntimeChanged = files.some(isAppRuntimePath);
  const hudEditorOrInstallChanged = files.some(isHudEditorOrInstallPath);
  const automationChanged = files.some(isReviewAutomationPath);
  const totalDelta = Number(pr.additions || 0) + Number(pr.deletions || 0);

  const notes = [];

  if (isSmoke) {
    messageFn("Review annotations smoke marker detected: advisory comment path is active.");
    notes.push("smoke marker detected");
  }

  if (smoke.placeholder) {
    warnFn("`Smoke:` evidence still looks like a template placeholder; replace it with setup/result/cleanup or a no-smoke reason/substitute.");
    notes.push("placeholder smoke evidence");
  }

  if (swiftSourceChanged && !swiftTestsChanged && !smoke.ok && !bodyHasNoTestRationale(body)) {
    warnFn("Swift source changed without Swift tests or smoke/no-test rationale. Add focused tests, real smoke evidence, or a no-test explanation.");
    notes.push("Swift source without tests/rationale");
  }

  if (hudEditorOrInstallChanged && !smoke.ok) {
    warnFn("HUD/editor/install/launch behavior changed without professional smoke evidence. Add `Smoke: setup=...; result=...; cleanup=...` or a no-smoke reason/substitute.");
    notes.push("HUD/editor/install path without smoke evidence");
  }

  if (totalDelta >= 500) {
    warnFn(`Large PR: ${totalDelta} changed lines. Consider splitting unless the change is mechanical or generated.`);
    notes.push("large PR warning");
  }

  if (automationChanged) {
    messageFn("Review automation changed; verify the exact PR head SHA and observe Review Annotations before treating the lane as calibrated.");
    notes.push("automation changed");
  }

  if (appRuntimeChanged && !smoke.ok && !automationChanged) {
    messageFn("SpotNote runtime changed; make sure `make ci` and a real or headless smoke are represented in the PR evidence.");
    notes.push("runtime proof reminder");
  }

  if (notes.length > 0) {
    markdownFn([
      "### Review annotations",
      "- Mode: advisory only; this Dangerfile does not call `fail()`.",
      `- Changed files observed: ${files.length}`,
      `- Changed lines observed: ${totalDelta}`,
      `- Notes: ${notes.join("; ")}`,
    ].join("\n"));
  }

  return {
    files,
    isSmoke,
    smoke,
    swiftSourceChanged,
    swiftTestsChanged,
    appRuntimeChanged,
    hudEditorOrInstallChanged,
    automationChanged,
    totalDelta,
    notes,
  };
}

if (typeof danger !== "undefined") {
  runSpotNoteDanger({ danger, warn, message, markdown });
}

module.exports = {
  changedFiles,
  isSwiftSource,
  isSwiftTest,
  isAppRuntimePath,
  isHudEditorOrInstallPath,
  isReviewAutomationPath,
  runSpotNoteDanger,
  smokeEvidence,
};

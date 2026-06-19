#!/usr/bin/env python3
"""Static launch contract smoke for SpotNote's HUD-first startup behavior.

This is intentionally source-only: it does not launch, install, hide Dock icons,
or mutate user defaults. It protects the brittle AppKit ordering that makes a
normal app open produce a visible HUD while still allowing SpotNote to hide from
the Dock when idle.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_contains(text: str, needle: str, label: str) -> None:
    if needle not in text:
        fail(f"missing {label}: {needle}")


def require_order(text: str, needles: list[str], label: str) -> None:
    position = -1
    for needle in needles:
        next_position = text.find(needle, position + 1)
        if next_position == -1:
            fail(f"missing {label} step after offset {position}: {needle}")
        position = next_position


def window(text: str, marker: str, length: int, label: str) -> str:
    start = text.find(marker)
    if start == -1:
        fail(f"missing {label} marker: {marker}")
    return text[start : start + length]


def check_app_delegate() -> None:
    app = read("Sources/SpotNoteApp/AppDelegate.swift")

    launch_setup = window(app, "func applicationDidFinishLaunching", 950, "launch setup")
    require_order(
        launch_setup,
        [
            "MainMenu.install",
            "observeUpdateNotifications()",
            "if isHeadlessTestLaunch",
            "_ = spotlight",
            "writeHeadlessReadyMarker()",
            "return",
            "enableLaunchAtLoginIfFirstRun()",
            "installGlobalHotkeys()",
            "presentInitialSurface()",
        ],
        "headless launch returns before user-visible launch side effects",
    )
    require_contains(app, "SPOTNOTE_HEADLESS_TEST", "headless smoke environment flag")
    require_contains(app, "SpotNote headless test launch ready", "headless smoke readiness marker")

    launch_block = window(app, "let didPresentOnboarding = presentOnboardingIfNeeded()", 650, "launch path")
    require_order(
        launch_block,
        [
            "if !didPresentOnboarding",
            "DispatchQueue.main.async",
            "self.spotlight.openHUD()",
            "self.installMenuBarIfNeeded()",
            "} else {",
            "installMenuBarIfNeeded()",
        ],
        "normal launch opens HUD before installing menu bar",
    )

    require_contains(app, "onWillShowHUD: {", "HUD show callback wiring")
    require_contains(app, "DockIconSwitcher.applyVisibility(true)", "Dock visible before HUD")
    require_contains(app, "onDidHideHUD: { [weak self] in", "HUD hide callback wiring")
    require_contains(app, "self?.applyDockVisibilityWhenIdle()", "idle Dock hide callback")

    dock_idle = window(app, "private func applyDockVisibilityWhenIdle()", 500, "idle Dock policy")
    require_contains(dock_idle, "guard !preferences.showDockIcon else", "respect visible Dock preference")
    require_contains(dock_idle, "NSApp.windows.contains", "visible-window guard before accessory mode")
    require_order(
        dock_idle,
        [
            "let hasVisibleWindow = NSApp.windows.contains",
            "guard !hasVisibleWindow else { return }",
            "DockIconSwitcher.applyVisibility(false)",
        ],
        "hide Dock only after windows close",
    )

    onboarding = window(app, "private func presentOnboardingIfNeeded()", 850, "onboarding launch path")
    require_order(
        onboarding,
        [
            "guard OnboardingController.shouldShow() else { return false }",
            "onboarding = controller",
            "DispatchQueue.main.async { [weak controller] in controller?.show() }",
            "return true",
        ],
        "first-run onboarding is deferred and suppresses immediate HUD",
    )
    require_contains(onboarding, "self.spotlight.openHUD()", "HUD opens when onboarding finishes")

    reopen = window(app, "func applicationShouldHandleReopen", 520, "reopen path")
    require_order(
        reopen,
        [
            "if OnboardingController.shouldShow()",
            "_ = presentOnboardingIfNeeded()",
            "else if onboarding?.isActive == true",
            "onboarding?.handleGlobalToggleChord()",
            "else",
            "spotlight.openHUD()",
            "return true",
        ],
        "app reopen routes to onboarding or HUD",
    )


def check_spotlight_window() -> None:
    spotlight = read("Sources/Spotlight/SpotlightWindow.swift")
    require_contains(spotlight, "private let onWillShowHUD: () -> Void", "HUD show callback storage")
    require_contains(spotlight, "private let onDidHideHUD: () -> Void", "HUD hide callback storage")

    focus = window(spotlight, "private func focusOrShow()", 700, "HUD focus path")
    require_order(
        focus,
        [
            "onWillShowHUD()",
            "let panel = panel ?? makePanel()",
            "NSApp.activate(ignoringOtherApps: true)",
            "bringPanelToFront(panel)",
        ],
        "HUD makes app regular before panel activation",
    )

    close = window(spotlight, "let target = previouslyActiveApp", 240, "HUD close path")
    require_order(
        close,
        [
            "previouslyActiveApp = nil",
            "NSApp.hide(nil)",
            "onDidHideHUD()",
        ],
        "HUD close reapplies idle Dock policy after hiding",
    )


def check_info_plist() -> None:
    plist = read("App/Info.plist")
    if "<key>LSUIElement</key>" in plist and "<true/>" in plist:
        fail("source Info.plist still declares LSUIElement=true")


if __name__ == "__main__":
    check_info_plist()
    check_app_delegate()
    check_spotlight_window()
    print("OK: SpotNote launch contract smoke passed")

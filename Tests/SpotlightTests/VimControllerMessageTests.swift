import Testing

@testable import Spotlight

@MainActor
@Suite("Vim controller transient messages")
struct VimControllerMessageTests {
  @Test("toast messages clear after the display window")
  func toastMessagesClearAfterDisplayWindow() async throws {
    let controller = VimController()

    controller.showMessage("Created PER-999 in Linear", kind: .success, icon: .hermes)
    #expect(controller.message?.text == "Created PER-999 in Linear")

    try await waitUntil { controller.message == nil }
  }

  private func waitUntil(condition: @MainActor @escaping () -> Bool) async throws {
    for _ in 0..<80 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("message did not clear")
  }
}

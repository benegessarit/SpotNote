import Foundation
import Testing

@testable import Spotlight

@Suite("Scratchpad Linear handoff")
struct ScratchpadHandoffTests {
  @Test("Linear payload uses the local-ingress Linear intent")
  func linearPayloadIntent() throws {
    let payload = try ScratchpadHandoffClient.payload(forLinearTask: "Call Elliot", id: "spotnote-linear-task:test")
    #expect(payload.id == "spotnote-linear-task:test")
    #expect(payload.intent == "linear_issue")
    #expect(payload.source.app == "SpotNote")
    #expect(payload.source.title == "Linear task")
    #expect(payload.text.contains("Task title:\nCall Elliot"))
  }

  @Test("title normalizer strips SpotNote checklist and priority markup")
  func titleNormalizerStripsMarkup() {
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "! [ ] Call Elliot") == "Call Elliot")
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "- ☑ Wipe mac") == "Wipe mac")
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "◆ [x] Send note") == "Send note")
  }

  @Test("blank Linear title is rejected")
  func blankTitleRejected() {
    #expect(throws: ScratchpadHandoffError.emptyText) {
      _ = try ScratchpadHandoffClient.payload(forLinearTask: "   ", id: "spotnote-linear-task:test")
    }
  }
}

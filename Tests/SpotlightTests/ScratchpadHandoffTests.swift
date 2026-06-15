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
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "◆ [ x ] Send note") == "Send note")
  }

  @Test("blank Linear title is rejected")
  func blankTitleRejected() {
    #expect(throws: ScratchpadHandoffError.emptyText) {
      _ = try ScratchpadHandoffClient.payload(forLinearTask: "   ", id: "spotnote-linear-task:test")
    }
  }

  @Test("local-ingress snake-case capture_id is decoded into the handoff receipt")
  func snakeCaseCaptureIDReceipt() async throws {
    let response = #"{"accepted":true,"capture_id":"spotnote-linear-task:test"}"#.data(using: .utf8) ?? Data()
    let client = ScratchpadHandoffClient(
      endpoint: URL(string: "http://127.0.0.1:8645/api/local-ingress/marginal")!,
      session: StubURLSession(data: response, statusCode: 202)
    )

    let receipt = try await client.sendLinearTask(title: "Call Elliot", id: "spotnote-linear-task:test")

    #expect(receipt.captureID == "spotnote-linear-task:test")
  }
}

private final class StubURLSession: URLSessionProtocol, @unchecked Sendable {
  let data: Data
  let statusCode: Int

  init(data: Data, statusCode: Int) {
    self.data = data
    self.statusCode = statusCode
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "http://127.0.0.1")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    ) ?? HTTPURLResponse()
    return (data, response)
  }
}

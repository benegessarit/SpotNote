import Foundation
import Testing

@testable import Spotlight

@Suite("Scratchpad Linear handoff")
struct ScratchpadHandoffTests {
  @Test("Linear payload uses the local-ingress Linear intent")
  func linearPayloadIntent() throws {
    let payload = try ScratchpadHandoffClient.payload(
      forLinearTask: "Call Elliot",
      id: "spotnote-linear-task:test"
    )
    #expect(payload.id == "spotnote-linear-task:test")
    #expect(payload.intent == "linear_issue")
    #expect(payload.source.app == "SpotNote")
    #expect(payload.source.title == "Linear task")
    #expect(payload.text.contains("Task title:\nCall Elliot"))
  }

  @Test("Linear payload can request labels and Done status")
  func linearPayloadCanRequestDoneState() throws {
    let payload = try ScratchpadHandoffClient.payload(
      forLinearTask: LinearTaskHandoffRequest(
        title: "Call Elliot",
        targetStatus: .done,
        labels: ["Amplify"],
        dueDate: "2026-06-15"
      ),
      id: "spotnote-linear-task:test"
    )

    #expect(payload.text.contains("State/status: Done"))
    #expect(payload.text.contains("Labels to apply if assignable: Amplify"))
    #expect(payload.text.contains("Due date: 2026-06-15"))
    #expect(payload.text.contains("Task title:\nCall Elliot"))
  }

  @Test("Linear request parser extracts labels and due dates from task text")
  func linearRequestParserExtractsLabelsAndDueDates() throws {
    let today = try #require(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 14))
    )
    let request = try #require(
      LinearTaskMetadataParser.request(
        from: "- call LP #Amplify #Bio due:tomorrow",
        targetStatus: .planned,
        today: today
      )
    )

    #expect(request.title == "call LP")
    #expect(request.targetStatus == .planned)
    #expect(request.labels == ["Amplify", "Bio"])
    #expect(request.dueDate == "2026-06-15")
  }

  @Test("Linear request parser supports explicit MM-dd-yyyy due dates")
  func linearRequestParserSupportsExplicitDueDates() throws {
    let request = try #require(
      LinearTaskMetadataParser.request(
        from: "Review deck due:06-15-2026 #Amplify",
        targetStatus: .done,
        today: Date(timeIntervalSince1970: 0)
      )
    )

    #expect(request.title == "Review deck")
    #expect(request.labels == ["Amplify"])
    #expect(request.dueDate == "2026-06-15")
  }

  @Test("title normalizer strips SpotNote checklist and priority markup")
  func titleNormalizerStripsMarkup() {
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "! [ ] Call Elliot") == "Call Elliot")
    #expect(
      LinearTaskTitleNormalizer.title(fromSpotNoteLine: "! [   ] Call Elliot") == "Call Elliot"
    )
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "- ☑ Wipe mac") == "Wipe mac")
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "◆ [x] Send note") == "Send note")
    #expect(LinearTaskTitleNormalizer.title(fromSpotNoteLine: "◆ [ x ] Send note") == "Send note")
  }

  @Test("Linear prompt does not block issue creation on missing source labels")
  func linearPromptDoesNotBlockIssueCreationOnMissingSourceLabels() throws {
    let payload = try ScratchpadHandoffClient.payload(
      forLinearTask: LinearTaskHandoffRequest(
        title: "a task",
        targetStatus: .triage,
        labels: ["Amplify", "FatFingerTypo"],
        dueDate: nil
      ),
      id: "spotnote-linear-task:test"
    )

    #expect(payload.text.contains("Labels to apply if assignable: Amplify, FatFingerTypo"))
    #expect(payload.text.contains("Do not block issue creation on a missing label"))
    #expect(payload.text.contains("Treat labels as optional best-effort metadata"))
    #expect(!payload.text.contains("Spotnote"))
    #expect(!payload.text.contains("do not silently create a partial issue"))
  }

  @Test("blank Linear title is rejected")
  func blankTitleRejected() {
    #expect(throws: ScratchpadHandoffError.emptyText) {
      _ = try ScratchpadHandoffClient.payload(forLinearTask: "   ", id: "spotnote-linear-task:test")
    }
  }

  @Test("local-ingress snake-case capture_id is decoded into the handoff receipt")
  func snakeCaseCaptureIDReceipt() async throws {
    let response = Data(#"{"accepted":true,"capture_id":"spotnote-linear-task:test"}"#.utf8)
    let endpoint = try #require(URL(string: "http://127.0.0.1:8645/api/local-ingress/marginal"))
    let client = ScratchpadHandoffClient(
      endpoint: endpoint,
      session: StubURLSession(data: response, statusCode: 202)
    )

    let receipt = try await client.sendLinearTask(
      title: "Call Elliot",
      id: "spotnote-linear-task:test"
    )

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
    let response =
      HTTPURLResponse(
        url: request.url ?? URL(fileURLWithPath: "/"),
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      ) ?? HTTPURLResponse()
    return (data, response)
  }
}

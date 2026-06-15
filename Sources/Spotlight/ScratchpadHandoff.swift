import Foundation

struct ScratchpadHandoffClient: Sendable {
  static let defaultEndpoint: URL = {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = 8645
    components.path = "/api/local-ingress/marginal"
    guard let url = components.url else { preconditionFailure("Invalid local ingress URL") }
    return url
  }()

  var endpoint: URL = Self.defaultEndpoint
  var session: URLSessionProtocol = URLSession.shared

  func sendLinearTask(title: String, id: String = Self.linearTaskID()) async throws -> ScratchpadHandoffReceipt {
    let payload = try Self.payload(forLinearTask: title, id: id)
    return try await send(payload: payload)
  }

  private func send(payload: ScratchpadHandoffPayload) async throws -> ScratchpadHandoffReceipt {
    let body = try JSONEncoder().encode(payload)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ScratchpadHandoffError.badResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw ScratchpadHandoffError.rejected(statusCode: http.statusCode)
    }
    return try Self.receipt(from: data)
  }

  static func payload(forLinearTask rawTitle: String, id: String) throws -> ScratchpadHandoffPayload {
    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw ScratchpadHandoffError.emptyText }
    return ScratchpadHandoffPayload(
      id: id,
      intent: "linear_issue",
      text: LinearTaskHandoffPrompt.render(title: title),
      source: ScratchpadHandoffPayload.Source(app: "SpotNote", title: "Linear task")
    )
  }

  private static func receipt(from data: Data) throws -> ScratchpadHandoffReceipt {
    if data.isEmpty { return ScratchpadHandoffReceipt(captureID: nil) }
    let decoded = try JSONDecoder().decode(LocalIngressResponse.self, from: data)
    guard decoded.accepted else { throw ScratchpadHandoffError.notAccepted }
    return ScratchpadHandoffReceipt(captureID: decoded.captureID)
  }

  private static func linearTaskID() -> String {
    "spotnote-linear-task:\(UUID().uuidString.lowercased())"
  }
}

protocol URLSessionProtocol: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

struct ScratchpadHandoffPayload: Codable, Equatable, Sendable {
  struct Source: Codable, Equatable, Sendable {
    let app: String
    let title: String
  }

  let id: String
  let intent: String
  let text: String
  let source: Source
}

struct ScratchpadHandoffReceipt: Equatable, Sendable {
  let captureID: String?
}

enum ScratchpadHandoffError: Error, Equatable {
  case emptyText
  case badResponse
  case rejected(statusCode: Int)
  case notAccepted
}

private struct LocalIngressResponse: Codable {
  let accepted: Bool
  let captureID: String?
}

enum LinearTaskTitleNormalizer {
  static func title(fromSpotNoteLine rawLine: String) -> String? {
    let cleaned =
      rawLine
      .components(separatedBy: .newlines)
      .map(cleanSingleLine(_:))
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func cleanSingleLine(_ raw: String) -> String {
    var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    line = stripBullets(line)
    line = stripPriority(line)
    line = stripCheckbox(line)
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripBullets(_ raw: String) -> String {
    var line = raw
    while line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("•") {
      line.removeFirst()
      line = line.trimmingCharacters(in: .whitespaces)
    }
    return line
  }

  private static func stripPriority(_ raw: String) -> String {
    var line = raw
    while line.hasPrefix("!") || line.hasPrefix("◆") {
      line.removeFirst()
      line = line.trimmingCharacters(in: .whitespaces)
    }
    return line
  }

  private static func stripCheckbox(_ raw: String) -> String {
    var line = raw
    for marker in ["[ ]", "[x]", "[X]", "☐", "☑"] where line.hasPrefix(marker) {
      line.removeFirst(marker.count)
      return line.trimmingCharacters(in: .whitespaces)
    }
    return line
  }
}

enum LinearTaskHandoffPrompt {
  static func render(title: String) -> String {
    """
    SpotNote Linear task handoff.

    Create exactly one new Linear issue in David's personal Linear workspace.
    Required issue shape:
    - Team: David
    - State/status: Triage
    - Priority: none / 0
    - Assignee: none
    - Labels: none unless Linear requires an existing default
    - Title: use the exact task title below

    Do not preserve SpotNote checklist markers such as [ ], [x], bullets, or ! priority markers.
    Do not search for or update an existing issue; this motion explicitly creates a new Triage task.
    Reply with the created Linear identifier and URL, or the blocker if creation fails.

    Task title:
    \(title)
    """
  }
}

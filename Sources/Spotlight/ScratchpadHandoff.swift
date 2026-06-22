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

  func sendLinearTask(
    _ request: LinearTaskHandoffRequest,
    id: String = Self.linearTaskID()
  ) async throws -> ScratchpadHandoffReceipt {
    let payload = try Self.payload(forLinearTask: request, id: id)
    return try await send(payload: payload)
  }

  func sendLinearTask(
    title: String,
    id: String = Self.linearTaskID()
  ) async throws -> ScratchpadHandoffReceipt {
    let payload = try Self.payload(forLinearTask: LinearTaskHandoffRequest(title: title), id: id)
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
    try payload(forLinearTask: LinearTaskHandoffRequest(title: rawTitle), id: id)
  }

  static func payload(
    forLinearTask request: LinearTaskHandoffRequest,
    id: String
  ) throws -> ScratchpadHandoffPayload {
    let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw ScratchpadHandoffError.emptyText }
    let normalizedRequest = request.withTitle(title)
    return ScratchpadHandoffPayload(
      id: id,
      intent: "linear_issue",
      text: LinearTaskHandoffPrompt.render(request: normalizedRequest),
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

enum LinearTaskTargetStatus: String, Equatable, Sendable {
  case done = "Done"
  case planned = "Planned"
  case triage = "Triage"
  case started = "Started"
  case later = "Later"
}

struct LinearTaskHandoffRequest: Equatable, Sendable {
  let title: String
  let targetStatus: LinearTaskTargetStatus
  let labels: [String]
  let dueDate: String?

  init(
    title: String,
    targetStatus: LinearTaskTargetStatus = .triage,
    labels: [String] = [],
    dueDate: String? = nil
  ) {
    self.title = title
    self.targetStatus = targetStatus
    self.labels = labels
    self.dueDate = dueDate
  }

  func withTitle(_ title: String) -> Self {
    Self(title: title, targetStatus: targetStatus, labels: labels, dueDate: dueDate)
  }
}

enum ScratchpadHandoffError: Error, Equatable {
  case emptyText
  case badResponse
  case rejected(statusCode: Int)
  case notAccepted
}

private struct LocalIngressResponse: Decodable {
  let accepted: Bool
  let captureID: String?

  private enum CodingKeys: String, CodingKey {
    case accepted
    case captureID
    case captureIDSnake = "capture_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accepted = try container.decode(Bool.self, forKey: .accepted)
    captureID =
      try container.decodeIfPresent(String.self, forKey: .captureID)
      ?? container.decodeIfPresent(String.self, forKey: .captureIDSnake)
  }
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
    for marker in ["[   ]", "[ ]", "[ x ]", "[x]", "[X]", "☐", "☑"] where line.hasPrefix(marker) {
      line.removeFirst(marker.count)
      return line.trimmingCharacters(in: .whitespaces)
    }
    return line
  }
}

enum LinearTaskMetadataParser {
  static func request(
    from rawText: String,
    targetStatus: LinearTaskTargetStatus,
    today: Date = Date(),
    calendar: Calendar = Calendar.current
  ) -> LinearTaskHandoffRequest? {
    guard let cleaned = LinearTaskTitleNormalizer.title(fromSpotNoteLine: rawText) else {
      return nil
    }
    let labels = labels(in: cleaned)
    let dueDate = dueDate(in: cleaned, today: today, calendar: calendar)
    let title = strippedMetadata(from: cleaned)
    guard !title.isEmpty else { return nil }
    return LinearTaskHandoffRequest(
      title: title,
      targetStatus: targetStatus,
      labels: deduped(labels),
      dueDate: dueDate
    )
  }

  private static func labels(in text: String) -> [String] {
    matches(pattern: #"(?<!\S)#([A-Za-z][A-Za-z0-9_-]*)"#, in: text).compactMap { match in
      guard let range = Range(match.range(at: 1), in: text) else { return nil }
      return String(text[range])
    }
  }

  private static func dueDate(in text: String, today: Date, calendar: Calendar) -> String? {
    guard
      let match = matches(
        pattern: #"(?i)(?:^|\s)due:(today|tomorrow|\d{2}-\d{2}-\d{4})(?=\s|$)"#,
        in: text
      ).first,
      let valueRange = Range(match.range(at: 1), in: text)
    else { return nil }
    let value = String(text[valueRange]).lowercased()
    if value == "today" {
      return isoDateString(for: today, calendar: calendar)
    }
    if value == "tomorrow", let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
      return isoDateString(for: tomorrow, calendar: calendar)
    }
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return String(format: "%04d-%02d-%02d", parts[2], parts[0], parts[1])
  }

  private static func strippedMetadata(from text: String) -> String {
    let withoutLabels = replacing(pattern: #"(?<!\S)#[A-Za-z][A-Za-z0-9_-]*"#, in: text)
    let withoutDue = replacing(
      pattern: #"(?i)(?:^|\s)due:(today|tomorrow|\d{2}-\d{2}-\d{4})(?=\s|$)"#,
      in: withoutLabels
    )
    return
      withoutDue
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
  }

  private static func replacing(pattern: String, in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    return regex.stringByReplacingMatches(
      in: text,
      range: NSRange(location: 0, length: (text as NSString).length),
      withTemplate: " "
    )
  }

  private static func isoDateString(for date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  private static func deduped(_ labels: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for label in labels where !label.isEmpty {
      let key = label.lowercased()
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(label)
    }
    return result
  }
}

enum LinearTaskHandoffPrompt {
  static func render(request: LinearTaskHandoffRequest) -> String {
    let labelLine =
      request.labels.isEmpty
      ? "none"
      : request.labels.joined(separator: ", ")
    let dueDateLine = request.dueDate ?? "none"
    return """
      SpotNote Linear task handoff.

      Create exactly one new Linear issue in David's personal Linear workspace.
      Required issue shape:
      - Team: David
      - State/status: \(request.targetStatus.rawValue)
      - Priority: none / 0
      - Assignee: none
      - Labels to apply if assignable: \(labelLine)
      - Due date: \(dueDateLine)
      - Title: use the exact task title below

      Treat labels as optional best-effort metadata, not as required issue shape.
      Do not preserve SpotNote checklist markers such as [   ], [ ], [ x ], [x], bullets, #labels, due:* metadata, or ! priority markers.
      Do not search for or update an existing issue; this motion explicitly creates a new issue.
      If the requested state/status or due date cannot be applied, reply with the blocker.
      Do not block issue creation on a missing label; create the issue without missing labels and mention any skipped labels in the reply.
      Reply with the created Linear identifier and URL, or the blocker if creation fails.

      Task title:
      \(request.title)
      """
  }
}

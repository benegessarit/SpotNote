import AppKit
import WebKit

/// Renders link previews the way the source component's screenshot API
/// does -- a dark-mode page capture at 2.5x the display size -- but fully
/// locally: an offscreen ephemeral WKWebView, snapshotted after load and
/// cached per URL for the app's lifetime. Fetches happen only when a card
/// actually opens (hover), never on paste.
@MainActor
final class LinkSnapshotter: NSObject {
  static let shared = LinkSnapshotter()

  private var cache: [URL: NSImage] = [:]
  private var waiters: [URL: [(NSImage?) -> Void]] = [:]
  private var queue: [(url: URL, dark: Bool)] = []
  private var current: URL?
  private var webView: WKWebView?
  private var settleTimer: Timer?
  private var timeoutTimer: Timer?

  /// Capture scale mirroring the component's viewport.width = 2.5x.
  private static let captureScale: CGFloat = 2.5
  private static let loadTimeout: TimeInterval = 8
  private static let settleDelay: TimeInterval = 0.4

  func snapshot(_ url: URL, darkAppearance: Bool, completion: @escaping (NSImage?) -> Void) {
    if let cached = cache[url] {
      completion(cached)
      return
    }
    waiters[url, default: []].append(completion)
    guard current != url else { return }
    guard current == nil else {
      if !queue.contains(where: { $0.url == url }) {
        queue.append((url, darkAppearance))
      }
      return
    }
    begin(url: url, dark: darkAppearance)
  }

  private func begin(url: URL, dark: Bool) {
    current = url
    let size = LinkPreviewMetrics.imageSize
    let frame = NSRect(
      x: 0,
      y: 0,
      width: size.width * Self.captureScale,
      height: size.height * Self.captureScale
    )
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: frame, configuration: configuration)
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    view.navigationDelegate = self
    webView = view
    timeoutTimer = Timer.scheduledTimer(
      withTimeInterval: Self.loadTimeout,
      repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.finish(image: nil) }
    }
    view.load(URLRequest(url: url))
  }

  private func capture() {
    guard let webView else { return }
    let configuration = WKSnapshotConfiguration()
    configuration.snapshotWidth = NSNumber(value: Double(LinkPreviewMetrics.imageSize.width))
    webView.takeSnapshot(with: configuration) { [weak self] image, _ in
      MainActor.assumeIsolated { self?.finish(image: image) }
    }
  }

  private func finish(image: NSImage?) {
    settleTimer?.invalidate()
    settleTimer = nil
    timeoutTimer?.invalidate()
    timeoutTimer = nil
    webView?.navigationDelegate = nil
    webView = nil
    guard let url = current else { return }
    current = nil
    if let image {
      cache[url] = image
    }
    let callbacks = waiters.removeValue(forKey: url) ?? []
    for callback in callbacks {
      callback(image)
    }
    if !queue.isEmpty {
      let next = queue.removeFirst()
      begin(url: next.url, dark: next.dark)
    }
  }
}

extension LinkSnapshotter: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    settleTimer?.invalidate()
    // Brief settle so late-painting hero content lands in the capture.
    settleTimer = Timer.scheduledTimer(
      withTimeInterval: Self.settleDelay,
      repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.capture() }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    finish(image: nil)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    finish(image: nil)
  }
}

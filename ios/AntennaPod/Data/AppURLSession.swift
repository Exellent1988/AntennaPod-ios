import Foundation

/// Shared `URLSession` factory with optional HTTP(S) proxy (`AppHTTPProxy`) applied via
/// `URLSessionConfiguration.connectionProxyDictionary`.
/// Replaces ad-hoc `URLSession.shared` for feed refresh, search, chapters, transcripts, gpodder, etc.
/// Recreates when proxy prefs change (enable / host / port / username / password).
///
/// **Honest:** stock `AVPlayer` streaming is **not** routed through this session.
enum AppURLSession {
    private static let lock = NSLock()
    private static var cached: URLSession?
    private static var cachedSignature: String?

    /// Session with current proxy configuration (or none when proxy disabled / invalid).
    static var shared: URLSession {
        lock.lock()
        defer { lock.unlock() }
        let signature = AppHTTPProxy.configurationSignature()
        if let cached, cachedSignature == signature {
            return cached
        }
        cached?.finishTasksAndInvalidate()
        let config = URLSessionConfiguration.default
        AppHTTPProxy.apply(to: config)
        let session = URLSession(configuration: config)
        cached = session
        cachedSignature = signature
        return session
    }

    /// Drop the cached session so the next `shared` access rebuilds with current prefs.
    /// Safe to call from Settings `didSet` / notification handlers.
    static func invalidate() {
        lock.lock()
        cached?.finishTasksAndInvalidate()
        cached = nil
        cachedSignature = nil
        lock.unlock()
    }

    /// Apply current proxy to an existing configuration (e.g. background download session).
    static func applyProxy(to configuration: URLSessionConfiguration) {
        AppHTTPProxy.apply(to: configuration)
    }
}

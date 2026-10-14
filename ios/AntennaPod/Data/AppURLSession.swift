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
        // URLSession does not answer an HTTP 407 from the proxy dictionary's username/password
        // keys; without a delegate feeds, search, chapters, transcripts and gpodder failed behind
        // an authenticated proxy while downloads (own delegate) worked.
        let session = URLSession(configuration: config, delegate: ProxyAuthDelegate(), delegateQueue: nil)
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

/// Answers authenticated-proxy challenges with the Keychain proxy credentials (same rule as the
/// download session delegate). Every other challenge keeps the system default handling.
private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.isProxy() else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodDefault
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // A rejected username/password must not loop.
        guard challenge.previousFailureCount == 0,
              let proxy = AppHTTPProxy.resolved(),
              proxy.hasCredentials
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let credential = URLCredential(
            user: proxy.username,
            password: proxy.password,
            persistence: .forSession
        )
        completionHandler(.useCredential, credential)
    }
}

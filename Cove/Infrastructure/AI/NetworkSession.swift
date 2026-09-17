import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Never forward a provider credential or conversation through an HTTP redirect.
final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum NetworkSession {
    static func make() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }

    static func readableError(_ error: Error) -> String {
        if let value = error as? ChatError { return value.localizedDescription }
        if let value = error as? URLError {
            switch value.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
                 .timedOut, .dnsLookupFailed, .dataNotAllowed:
                return ChatError.disconnected.localizedDescription
            case .appTransportSecurityRequiresSecureConnection:
                return "macOS blocked this connection. Check the local-network permission and the base URL."
            default: break
            }
        }
        return "The provider could not complete this request. The partial response was kept. Check the connection and model."
    }
}

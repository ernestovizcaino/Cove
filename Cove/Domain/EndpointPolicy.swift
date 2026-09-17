import Foundation

/// HTTP is opt-in for literal private/loopback addresses and .local names only.
/// A provider called "Ollama" is not automatically considered local.
enum EndpointPolicy {
    static func baseURL(_ string: String) throws -> URL {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: cleaned),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ChatError.invalidEndpoint
        }
        guard scheme == "https" || isLocalHost(host) else { throw ChatError.insecureEndpoint }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        let forbidden = ["/api/chat", "/chat/completions", "/messages", "/responses"]
        guard !forbidden.contains(where: components.path.hasSuffix), let url = components.url else {
            throw ChatError.invalidEndpoint
        }
        return url
    }

    static func isLocalHost(_ raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if host == "::1" { return true }
        if host.contains(":") {
            // IPv6 ULA/link-local literal, not a domain beginning with "fc".
            return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:")
        }
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }
        return numbers[0] == 127 || numbers[0] == 10
            || (numbers[0] == 192 && numbers[1] == 168)
            || (numbers[0] == 172 && (16...31).contains(numbers[1]))
            || (numbers[0] == 169 && numbers[1] == 254)
    }

    static func isLocal(_ endpoint: String) -> Bool {
        guard let url = try? baseURL(endpoint), let host = url.host else { return false }
        return isLocalHost(host)
    }

    static func consentKey(for connection: ProviderConnection) throws -> String {
        "\(connection.id.uuidString)|\(try baseURL(connection.endpoint).absoluteString)"
    }

    static func validateEndpoint(_ connection: ProviderConnection) throws {
        let url = try baseURL(connection.endpoint)
        if connection.kind == .ollama {
            guard !["/api", "/v1"].contains(where: url.path.hasSuffix) else { throw ChatError.invalidEndpoint }
        }
        if connection.provider.id == "cloudflare" {
            let segments = url.path.split(separator: "/").map(String.init)
            guard url.host == "api.cloudflare.com", segments.count == 6,
                  Array(segments.prefix(3)) == ["client", "v4", "accounts"],
                  Array(segments.suffix(2)) == ["ai", "v1"],
                  segments[3].count == 32, segments[3].allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw ChatError.provider("Enter your 32-character Cloudflare account ID in the API base URL. For other gateways use a custom provider.")
            }
        }
        _ = try connection.additionalHeaders()
    }

    static func validate(_ connection: ProviderConnection) throws {
        try validateEndpoint(connection)
        guard !connection.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.missingModel
        }
    }
}

import CryptoKit
import Foundation

/// Only browse GET responses enter this cache. Authentication responses never do.
nonisolated enum ABSResponseCache {
    static func url(connection: ABSConnection, path: [String], query: [URLQueryItem]) -> URL {
        let identity = connection.baseURL.absoluteString + "\n" + (connection.username ?? "")
        let request = path.joined(separator: "/") + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audiobookshelf", isDirectory: true)
        return root.appendingPathComponent(hash(identity), isDirectory: true)
            .appendingPathComponent(hash(request) + ".json")
    }

    static func read(at url: URL) -> Data? { try? Data(contentsOf: url) }

    static func write(_ data: Data, at url: URL) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let safe = try? JSONSerialization.data(withJSONObject: scrub(object)) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try safe.write(to: url, options: .atomic)
        } catch { /* Caches may be evicted or unavailable without affecting browsing. */ }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func scrub(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.filter {
                let key = $0.key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                return !["token", "accesstoken", "refreshtoken", "apikey", "password", "authorization"].contains(key)
            }
                .mapValues(scrub)
        }
        if let array = value as? [Any] { return array.map(scrub) }
        if let text = value as? String, var components = URLComponents(string: text), components.queryItems != nil {
            components.queryItems = components.queryItems?.filter {
                !["token", "access_token", "refresh_token", "api_key", "apikey"].contains($0.name.lowercased())
            }
            components.user = nil
            components.password = nil
            return components.string ?? text
        }
        return value
    }
}

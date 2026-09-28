import Foundation

nonisolated enum ABSCredential: Codable, Equatable, Sendable {
    case session(accessToken: String, refreshToken: String)
    case apiKey(String)
}

nonisolated struct ABSConnection: Codable, Equatable, Sendable {
    let baseURL: URL
    let credential: ABSCredential
}

nonisolated protocol ABSCredentialStoring: Sendable {
    func load() throws -> ABSConnection?
    func save(_ connection: ABSConnection) throws
    func clear() throws
}

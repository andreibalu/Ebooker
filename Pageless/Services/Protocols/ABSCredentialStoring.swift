import Foundation

nonisolated enum ABSCredential: Codable, Equatable, Sendable {
    case session(accessToken: String, refreshToken: String)
    case apiKey(String)
}

nonisolated struct ABSConnection: Codable, Equatable, Sendable {
    let baseURL: URL
    let credential: ABSCredential
    /// Display-only ("Signed in as …"). Optional so a connection saved before it existed decodes.
    var username: String? = nil

    init(baseURL: URL, credential: ABSCredential, username: String? = nil) {
        self.baseURL = baseURL
        self.credential = credential
        self.username = username
    }
}

nonisolated protocol ABSCredentialStoring: Sendable {
    func load() throws -> ABSConnection?
    func save(_ connection: ABSConnection) throws
    func clear() throws
}

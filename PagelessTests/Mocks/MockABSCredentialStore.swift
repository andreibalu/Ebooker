import Foundation
@testable import Pageless

final class MockABSCredentialStore: ABSCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ABSConnection?

    init(_ connection: ABSConnection? = nil) { stored = connection }

    func load() throws -> ABSConnection? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func save(_ connection: ABSConnection) throws {
        lock.lock(); defer { lock.unlock() }
        stored = connection
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

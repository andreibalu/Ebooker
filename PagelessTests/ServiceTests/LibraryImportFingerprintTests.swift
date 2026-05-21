//
//  LibraryImportFingerprintTests.swift
//  PagelessTests
//

import Foundation
import Testing
@testable import Pageless

struct LibraryImportFingerprintTests {
    @Test func fingerprintIsDeterministicForSameBytes() async throws {
        let url = try makeTempFile(named: "a.bin", bytes: bytes(count: 4096, pattern: 0xAB))
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await LibraryImportService.fingerprint(url: url, durationSeconds: 12.5)
        let second = await LibraryImportService.fingerprint(url: url, durationSeconds: 12.5)
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func fingerprintDiffersAcrossDifferentBytes() async throws {
        let a = try makeTempFile(named: "a.bin", bytes: bytes(count: 4096, pattern: 0xAB))
        let b = try makeTempFile(named: "b.bin", bytes: bytes(count: 4096, pattern: 0xCD))
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        let fpA = await LibraryImportService.fingerprint(url: a, durationSeconds: 10)
        let fpB = await LibraryImportService.fingerprint(url: b, durationSeconds: 10)
        #expect(fpA != nil)
        #expect(fpB != nil)
        #expect(fpA != fpB)
    }

    @Test func fingerprintHandlesSmallFiles() async throws {
        // Smaller than 2MB cutoff → whole-file hash branch.
        let url = try makeTempFile(named: "small.bin", bytes: bytes(count: 1024, pattern: 0x42))
        defer { try? FileManager.default.removeItem(at: url) }

        let fp = await LibraryImportService.fingerprint(url: url, durationSeconds: 1)
        #expect(fp != nil)
        #expect(fp?.count == 64)
    }

    @Test func fingerprintIsRobustToFilenameChange() async throws {
        let payload = bytes(count: 8 * 1024, pattern: 0x77)
        let urlA = try makeTempFile(named: "first-name.bin", bytes: payload)
        let urlB = try makeTempFile(named: "second-name.bin", bytes: payload)
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let fpA = await LibraryImportService.fingerprint(url: urlA, durationSeconds: 4)
        let fpB = await LibraryImportService.fingerprint(url: urlB, durationSeconds: 4)
        #expect(fpA == fpB)
    }

    @Test func fingerprintReturnsNilForMissingFile() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("definitely-does-not-exist-\(UUID()).bin")
        let fp = await LibraryImportService.fingerprint(url: missing, durationSeconds: 1)
        #expect(fp == nil)
    }

    // MARK: - Helpers

    private func bytes(count: Int, pattern: UInt8) -> Data {
        Data(repeating: pattern, count: count)
    }

    private func makeTempFile(named name: String, bytes: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }
}

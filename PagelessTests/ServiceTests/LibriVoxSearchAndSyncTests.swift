import Foundation
import Testing
@testable import Pageless

@MainActor
struct LibriVoxSearchAndSyncTests {
    @Test func unrelatedHTTPFailuresRemainFailures() {
        let knownBody = Data(#"{"error":"Audiobooks could not be found"}"#.utf8)
        let unknownBody = Data(#"{"error":"Endpoint not found"}"#.utf8)
        for (body, status, allowsMissingBooks) in [
            (knownBody, 500, true),
            (unknownBody, 404, true),
            (Data("<html>Not found</html>".utf8), 404, true),
            (knownBody, 404, false)
        ] {
            #expect(throws: LibriVoxAPIError.self) {
                try LibriVoxAPIClient.validatedResponseData(
                    body, statusCode: status, allowsMissingBooks: allowsMissingBooks
                )
            }
        }
    }

}

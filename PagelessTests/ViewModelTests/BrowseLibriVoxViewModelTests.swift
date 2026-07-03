import SwiftData
import Testing
@testable import Pageless

@MainActor
struct BrowseLibriVoxViewModelTests {
    @Test func catalogBookResolvesExactLocalID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let book = makeBook(id: "book-42")
        context.insert(book)
        try context.save()

        let result = BrowseLibriVoxViewModel().catalogBook(
            id: "book-42",
            modelContext: context
        )

        #expect(result === book)
    }

    @Test func catalogBookReturnsNilForMissingID() throws {
        let container = try makeContainer()

        #expect(BrowseLibriVoxViewModel().catalogBook(
            id: "missing",
            modelContext: container.mainContext
        ) == nil)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LibriVoxBook.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeBook(id: String) -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: "Local Book",
            authorDisplay: "Local Author",
            bookDescription: "Description",
            language: "English",
            totalTimeSecs: 3_600
        )
    }
}

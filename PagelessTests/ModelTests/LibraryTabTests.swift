import Testing
@testable import Pageless

struct LibraryTabTests {
    @Test func visibleTitlesUseLibraryNaming() {
        #expect(LibraryTab.favorites.title == "Favorites")
        #expect(LibraryTab.allBooks.title == "Library")
        #expect(LibraryTab.freeBooks.title == "Free Books")
    }
}

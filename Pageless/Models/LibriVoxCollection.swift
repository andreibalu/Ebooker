//
//  LibriVoxCollection.swift
//  Pageless
//

import Foundation

/// A hand-curated, bundled shelf of LibriVox audiobooks shown on the Free Books tab.
///
/// Collections are static app content (no backend): each entry is a list of LibriVox
/// project IDs verified against the live feed API (librivox.org/api/feed/audiobooks).
/// Books resolve through the same local `LibriVoxBook` cache as the rest of the tab,
/// so a collection needs the network only for IDs not yet cached.
struct LibriVoxCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let bookIDs: [String]
}

extension LibriVoxCollection {
    static let all: [LibriVoxCollection] = [
        LibriVoxCollection(
            id: "ancient-wisdom",
            title: "Ancient Wisdom",
            subtitle: "Stoics, strategy & the examined life",
            iconSystemName: "laurel.leading",
            bookIDs: [
                "12252", // Meditations of the Emperor Marcus Aurelius Antoninus
                "15279", // Enchiridion — Epictetus
                "1358",  // Golden Sayings of Epictetus
                "18903", // On the Shortness of Life — Seneca
                "119",   // Art of War — Sun Tzu
            ]
        ),
        LibriVoxCollection(
            id: "gothic-horror",
            title: "Gothic & Horror",
            subtitle: "Vampires, monsters & haunted minds",
            iconSystemName: "moon.stars.fill",
            bookIDs: [
                "271", // Dracula — Bram Stoker
                "381", // Frankenstein — Mary Shelley
                "365", // Picture of Dorian Gray — Oscar Wilde
                "417", // Strange Case of Dr. Jekyll and Mr. Hyde — R. L. Stevenson
                "431", // Turn of the Screw — Henry James
                "977", // Carmilla — J. Sheridan Le Fanu
            ]
        ),
        LibriVoxCollection(
            id: "detective-mystery",
            title: "Detective & Mystery",
            subtitle: "Whodunits and master sleuths",
            iconSystemName: "magnifyingglass",
            bookIDs: [
                "314", // Adventures of Sherlock Holmes — Arthur Conan Doyle
                "901", // Hound of the Baskervilles — Arthur Conan Doyle
                "966", // Sign of the Four — Arthur Conan Doyle
                "424", // Innocence of Father Brown — G. K. Chesterton
                "635", // Moonstone — Wilkie Collins
            ]
        ),
        LibriVoxCollection(
            id: "grand-adventures",
            title: "Grand Adventures",
            subtitle: "Treasure, travel & daring escapes",
            iconSystemName: "map.fill",
            bookIDs: [
                "449", // Treasure Island — Robert Louis Stevenson
                "714", // Around the World in Eighty Days — Jules Verne
                "158", // Call of the Wild — Jack London
                "544", // King Solomon's Mines — H. Rider Haggard
                "120", // Three Musketeers — Alexandre Dumas
                "47",  // Count of Monte Cristo — Alexandre Dumas
            ]
        ),
        LibriVoxCollection(
            id: "love-society",
            title: "Love & Society",
            subtitle: "Romance, manners & sharp wit",
            iconSystemName: "heart.fill",
            bookIDs: [
                "253", // Pride and Prejudice — Jane Austen
                "133", // Jane Eyre — Charlotte Brontë
                "661", // Persuasion — Jane Austen
                "620", // Sense and Sensibility — Jane Austen
                "86",  // Emma — Jane Austen
                "911", // Wuthering Heights — Emily Brontë
            ]
        ),
        LibriVoxCollection(
            id: "short-listens",
            title: "Short Listens",
            subtitle: "Finished in an afternoon",
            iconSystemName: "clock.fill",
            bookIDs: [
                "15279", // Enchiridion — Epictetus (~47 min)
                "119",   // Art of War — Sun Tzu (~1.2 h)
                "18903", // On the Shortness of Life — Seneca (~1.6 h)
                "1126",  // Common Sense — Thomas Paine (~2 h)
                "140",   // Christmas Carol — Charles Dickens (~3.2 h)
                "417",   // Strange Case of Dr. Jekyll and Mr. Hyde (~3.1 h)
            ]
        ),
    ]
}

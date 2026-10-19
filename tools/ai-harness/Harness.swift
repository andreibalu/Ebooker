// Runs the app's moment and recap services on the host Mac's on-device model, one passage at a
// time, and writes one JSON line per passage. build.sh compiles it with the app's AI sources.
// Usage: harness <corpus.json> <moment|recap> <out.jsonl> [id,id,…]
import Foundation

struct Passage: Decodable { let id, book, kind, moment, recap: String }

@main
struct Harness {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4, ["moment", "recap"].contains(args[2]) else {
            print("usage: harness <corpus.json> <moment|recap> <out.jsonl> [id,id,…]")
            exit(2)
        }
        let corpus = try JSONDecoder().decode([Passage].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let mode = args[2]
        let only = args.count > 4 ? Set(args[4].split(separator: ",").map(String.init)) : nil
        FileManager.default.createFile(atPath: args[3], contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: args[3]))
        for passage in corpus where only?.contains(passage.id) ?? true {
            let start = Date()
            var row: [String: Any] = ["id": passage.id, "book": passage.book, "kind": passage.kind]
            do {
                if mode == "moment" {
                    let analysis = try await analyzeMoment(passage)
                    row["outcome"] = "named"
                    row["name"] = analysis.name
                    row["note"] = analysis.note
                    row["quote"] = analysis.quoteLine ?? ""
                    row["mood"] = analysis.mood?.rawValue ?? ""
                    row["categories"] = analysis.categories.map(\.rawValue)
                    row["characters"] = analysis.characters
                } else {
                    let recap = try await generateRecap(passage)
                    row["outcome"] = "recap"
                    row["recap"] = recap.recap
                    row["headline"] = recap.progressHeadline ?? ""
                }
            } catch {
                row["outcome"] = "error"
                row["error"] = String(describing: error)
                #if FALLBACK_NAMER
                if mode == "moment" {
                    row["fallbackName"] = MomentFallbackNamer.analysis(transcript: passage.moment, chapterTitle: nil, time: 754).name
                }
                #endif
            }
            row["seconds"] = Date().timeIntervalSince(start)
            handle.write(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
            handle.write(Data("\n".utf8))
            print(passage.id, row["outcome"]!, row["error"] ?? row["name"] ?? row["headline"] ?? "",
                  String(format: "%.1fs", row["seconds"] as! Double))
        }
    }

    // The service APIs changed with PR #84: build.sh defines PASSAGE_CONTEXT for sources that have
    // `AIPassageContext`, so one driver measures revisions on either side.
    static func analyzeMoment(_ passage: Passage) async throws -> MomentAnalysis {
        #if PASSAGE_CONTEXT
        try await MomentNamingService().analyzeMoment(transcript: passage.moment, context: AIPassageContext(bookTitle: passage.book))
        #else
        try await MomentNamingService().analyzeMoment(transcript: passage.moment, audiobookTitle: passage.book)
        #endif
    }

    static func generateRecap(_ passage: Passage) async throws -> RecapGenerationResult {
        #if PASSAGE_CONTEXT
        try await RecapService().generateRecap(transcript: passage.recap, context: AIPassageContext(bookTitle: passage.book), includeProgressHeadline: true)
        #else
        try await RecapService().generateRecap(transcript: passage.recap, audiobookTitle: passage.book, includeProgressHeadline: true)
        #endif
    }
}

//
//  AudioPlayerManagerLoadTests.swift
//  PagelessTests
//

import AVFoundation
import Foundation
import MediaPlayer
import Testing
@testable import Pageless

@MainActor
@Suite(.serialized)
struct AudioPlayerManagerLoadTests {

    @Test func slow_load_cannot_commit_after_fast_load() async {
        let slowGate = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(mixGate: slowGate))

        let slowLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: a, time: 11)
        }
        await waitUntilStarted(slowGate)

        let fastLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 22)
        }
        await fastLoad.value
        slowGate.release()
        await slowLoad.value

        assertCurrentPlayback(player, book: b, time: 22)
    }

    @Test func load_keeps_previous_item_state_until_new_item_commits() async {
        let newItemGate = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            mixGates: ["b.m4a": newItemGate]
        ))

        await player.playTrack(at: 0, in: a, time: 10)
        let newLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 22)
        }
        await waitUntilStarted(newItemGate)

        #expect(player.currentAudiobook === a)
        #expect(player.currentTrack === a.sortedTracks[0])
        #expect(player.currentTime == 10)
        #expect(player.persistence.lastPersistedTime == 10)
        #expect(b.currentTime == 0)
        #expect(b.lastPlayedAt == nil)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String == a.title)

        newItemGate.release()
        await newLoad.value
        assertCurrentPlayback(player, book: b, time: 22)
    }

    @Test func pause_during_load_keeps_previous_item_state_and_blocks_commit() async {
        let newItemGate = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            mixGates: ["b.m4a": newItemGate]
        ))

        await player.playTrack(at: 0, in: a, time: 10)
        let newLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 22)
        }
        await waitUntilStarted(newItemGate)

        player.pause()
        newItemGate.release()
        await newLoad.value

        #expect(player.currentAudiobook === a)
        #expect(player.currentTrack === a.sortedTracks[0])
        #expect(player.currentTime == 10)
        #expect(player.isPlaying == false)
        #expect(player.loadingPlaybackBookID == nil)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String == a.title)
    }

    @Test func manual_seek_during_load_cannot_mutate_committed_new_item() async {
        let newItemGate = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            mixGates: ["b.m4a": newItemGate]
        ))

        await player.playTrack(at: 0, in: a, time: 10)
        let newLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 22)
        }
        await waitUntilStarted(newItemGate)

        player.seek(to: 19)
        newItemGate.release()
        await newLoad.value
        await Task.yield()

        assertCurrentPlayback(player, book: b, time: 22)
    }

    @Test func rapid_track_loads_keep_only_newest_request_current() async {
        let slowGate = LoadGate()
        let book = makeBook(title: "Book", trackNames: ["a.m4a", "b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(mixGate: slowGate))

        let firstLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: book, time: 3)
        }
        await waitUntilStarted(slowGate)

        let secondLoad = Task { @MainActor in
            await player.playTrack(at: 1, in: book, time: 33)
        }
        await secondLoad.value
        slowGate.release()
        await firstLoad.value

        assertCurrentPlayback(player, book: book, trackIndex: 1, time: 33)
    }

    @Test func next_track_request_loses_to_newer_manual_book_selection() async {
        let firstGate = LoadGate()
        let nextGate = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a", "a-next.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            mixGates: ["a.m4a": firstGate, "a-next.m4a": nextGate]
        ))

        let firstLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: a, time: 1)
        }
        await waitUntilStarted(firstGate)
        firstGate.release()
        await firstLoad.value
        player.nextTrack()
        await waitUntilStarted(nextGate)
        let manualLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 44)
        }
        await manualLoad.value
        nextGate.release()

        assertCurrentPlayback(player, book: b, time: 44)
    }

    @Test func stale_failure_cannot_clear_newer_request() async {
        let slowDuration = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            duration: { asset in
                let name = Self.assetURL(asset).lastPathComponent
                if name == "a.m4a" {
                    await slowDuration.wait()
                    throw LoadTestError.failed
                }
                return CMTime(seconds: 60, preferredTimescale: 600)
            }
        ))

        let staleLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: a, time: 5)
        }
        await waitUntilStarted(slowDuration)

        let currentLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 55)
        }
        await currentLoad.value
        slowDuration.release()
        await staleLoad.value

        assertCurrentPlayback(player, book: b, time: 55)
        #expect(player.playerErrorMessage == nil)
    }

    @Test func stale_seek_completion_cannot_mutate_newer_request() async {
        let slowSeek = LoadGate()
        let a = makeBook(title: "A", trackNames: ["a.m4a"])
        let b = makeBook(title: "B", trackNames: ["b.m4a"])
        let player = AudioPlayerManager(loadPreparation: preparation(
            prepareSeek: { asset, _ in
                if Self.assetURL(asset).lastPathComponent == "a.m4a" {
                    await slowSeek.wait()
                }
                return true
            }
        ))

        let staleLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: a, time: 7)
        }
        await waitUntilStarted(slowSeek)

        let currentLoad = Task { @MainActor in
            await player.playTrack(at: 0, in: b, time: 77)
        }
        await currentLoad.value
        slowSeek.release()
        await staleLoad.value

        assertCurrentPlayback(player, book: b, time: 77)
    }

    private func preparation(
        mixGate: LoadGate? = nil,
        mixGates: [String: LoadGate] = [:],
        duration: @escaping @MainActor (AVAsset) async throws -> CMTime = { _ in
            CMTime(seconds: 60, preferredTimescale: 600)
        },
        prepareSeek: @escaping @MainActor (AVAsset, CMTime) async -> Bool = { _, _ in true }
    ) -> AudioPlayerLoadPreparation {
        AudioPlayerLoadPreparation(
            isNetworkAvailable: { true },
            makeAudioMix: { asset in
                let name = Self.assetURL(asset).lastPathComponent
                let gate = mixGates.isEmpty && name == "a.m4a" ? mixGate : mixGates[name]
                if let gate {
                    await gate.wait()
                }
                return nil
            },
            loadDuration: { asset in
                return try await duration(asset)
            },
            prepareSeek: prepareSeek
        )
    }

    private func makeBook(title: String, trackNames: [String]) -> Audiobook {
        let tracks = trackNames.enumerated().map { index, name in
            let track = AudioTrack(
                title: name,
                originalFileName: name,
                storedFileName: name,
                orderIndex: index,
                duration: 60
            )
            track.remoteURLString = "https://example.com/\(name)"
            return track
        }
        return Audiobook(
            title: title,
            folderName: title,
            isFreeBook: true,
            isDownloaded: false,
            tracks: tracks
        )
    }

    private func assertCurrentPlayback(
        _ player: AudioPlayerManager,
        book: Audiobook,
        trackIndex: Int = 0,
        time: Double
    ) {
        #expect(player.currentAudiobook === book)
        #expect(player.currentTrackIndex == trackIndex)
        #expect(player.currentTime == time)
        #expect(book.currentTrackIndex == trackIndex)
        #expect(book.currentTime == time)
        #expect(player.persistence.lastPersistedTime == time)
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String == book.title)
    }

    private func waitUntilStarted(_ gate: LoadGate) async {
        while !gate.started {
            await Task.yield()
        }
    }

    private static func assetURL(_ asset: AVAsset) -> URL {
        (asset as? AVURLAsset)?.url ?? URL(fileURLWithPath: "unknown.m4a")
    }
}

@MainActor
private final class LoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private enum LoadTestError: Error {
    case failed
}

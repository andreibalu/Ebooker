//
//  ICloudSettingsView.swift
//  Pageless
//

import SwiftData
import SwiftUI

struct ICloudSettingsView: View {
    /// Closure passed down from `SettingsView` so the Done pill dismisses the entire sheet.
    var onDismissSheet: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Query private var books: [Audiobook]

    @AppStorage(IcloudSyncGate.preferenceKey) private var iCloudSyncEnabled = false
    @AppStorage(CloudAudioStore.preferenceKey) private var storesAudio = false

    @State private var hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()
    @State private var showRelaunchAlert = false
    @State private var showAudioOnPrompt = false
    @State private var showAudioOffPrompt = false
    @State private var audioStore = CloudAudioStore.shared

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "iCloud Sync",
                titleStyle: .subview,
                backLabel: "Settings",
                onBack: { dismiss() },
                onDone: onDismissSheet
            )
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureCard
                    syncCard
                    audioCard

                    Text("iCloud Sync uses your private iCloud account, and Unpaged has no server of its own. Audio stored in iCloud counts toward your iCloud storage and moves over Wi-Fi, or over cellular when iCloud Drive may use cellular data.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsLegalLinks()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .settingsInteractiveBackGesture()
        .task {
            hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()
        }
        .alert("Relaunch Required", isPresented: $showRelaunchAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(relaunchMessage)
        }
        .confirmationDialog("Store audio in iCloud?", isPresented: $showAudioOnPrompt, titleVisibility: .visible) {
            Button("Store All \(booksToStore.count) Books") {
                storesAudio = true
                audioStore.storeAll(booksToStore)
            }
            Button("Only New Books") {
                storesAudio = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unpaged copies your imported books’ audio to iCloud Drive, so your other devices, or this iPhone after a reinstall, can download it. \(booksToStore.count == 1 ? "The book" : "The \(booksToStore.count) books") on this iPhone use about \(Self.byteCount(booksToStoreBytes)) of iCloud storage.")
        }
        .confirmationDialog("Stop storing audio in iCloud?", isPresented: $showAudioOffPrompt, titleVisibility: .visible) {
            Button("Keep Audio in iCloud") {
                storesAudio = false
            }
            Button("Remove Audio from iCloud", role: .destructive) {
                storesAudio = false
                audioStore.removeAllCloudAudio()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(audioOffMessage)
        }
    }

    private var featureCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keep titles, progress, moments, recaps and listening history in sync across your devices through your private iCloud account. Free with any iCloud account.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    featureBullet("All your titles")
                    featureBullet("Progress and bookmarks")
                    featureBullet("Saved moments and recaps")
                    featureBullet("EQ and playback preferences")
                    featureBullet("Your books’ audio, if you choose")
                }
            }
            .padding(16)
        }
    }

    private func featureBullet(_ label: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.amber.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.amber)
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private var syncCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { iCloudSyncEnabled },
                    set: { newValue in
                        guard newValue != iCloudSyncEnabled else { return }
                        iCloudSyncEnabled = newValue
                        if newValue != IcloudSyncGate.isEnabled() {
                            showRelaunchAlert = true
                        }
                    }
                )) {
                    SettingsRowLabel(title: "Sync library with iCloud", caption: syncCaption)
                }
                .disabled(!hasUbiquityIdentity)
                .accessibilityIdentifier("icloud.syncToggle")
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                SettingsHairline().padding(.leading, 4)

                NavigationLink {
                    CloudLibraryView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsRowLabel(
                            title: "iCloud Library",
                            caption: "See and manage everything backed up to iCloud"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(SettingsDesign.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("icloud.cloudLibrary")
            }
            .padding(12)
        }
    }

    private var audioCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { storesAudio },
                    set: { newValue in
                        guard newValue != storesAudio else { return }
                        if newValue {
                            if booksToStore.isEmpty { storesAudio = true } else { showAudioOnPrompt = true }
                        } else {
                            if audioStore.usage.books > 0 { showAudioOffPrompt = true } else { storesAudio = false }
                        }
                    }
                )) {
                    SettingsRowLabel(title: "Store audio in iCloud", caption: audioCaption)
                }
                .disabled(!audioStore.isActive)
                .accessibilityIdentifier("icloud.audioToggle")
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                if audioStore.isActive && (audioStore.usage.books > 0 || uploadingCount > 0) {
                    SettingsHairline().padding(.leading, 4)
                    Text(usageLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("icloud.audioUsage")
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                }

                if let error = audioStore.errorMessage {
                    SettingsHairline().padding(.leading, 4)
                    CloudAudioErrorRow(message: error) { audioStore.errorMessage = nil }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                }

                SettingsHairline().padding(.leading, 4)
                Text("Only books you import are stored. Free books and Audiobookshelf books download again from their source.")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
            }
            .padding(12)
        }
    }

    // MARK: - Copy

    private var syncCaption: String {
        if !hasUbiquityIdentity {
            return "Sign in to iCloud in System Settings to enable sync."
        }
        let activeThisLaunch = IcloudSyncGate.isEnabled()
        if iCloudSyncEnabled && !activeThisLaunch {
            return "Will turn on after relaunch"
        }
        if !iCloudSyncEnabled && activeThisLaunch {
            return "Will turn off after relaunch"
        }
        return iCloudSyncEnabled
            ? "On — your library syncs across devices"
            : "Off — library stays on this device"
    }

    private var audioCaption: String {
        switch audioStore.availability {
        case .syncOff:
            return iCloudSyncEnabled && hasUbiquityIdentity
                ? "Available after you reopen Unpaged with sync on."
                : "Turn on library sync to store audio as well."
        case .checking:
            return "Checking iCloud Drive…"
        case .driveUnavailable:
            return "Turn on iCloud Drive for Unpaged in the Settings app to store audio."
        case .available:
            return storesAudio
                ? "New books’ audio is copied to iCloud Drive, so other devices can download it."
                : "Off — each device keeps its own audio."
        }
    }

    private var usageLine: String {
        let usage = audioStore.usage
        var parts: [String] = []
        if usage.books > 0 {
            parts.append("\(usage.books) \(usage.books == 1 ? "book" : "books") · \(Self.byteCount(usage.bytes)) in iCloud")
        }
        if quotaExceededCount > 0 {
            parts.append("iCloud storage is full")
        } else if uploadingCount > 0 {
            parts.append("Uploading \(uploadingCount) \(uploadingCount == 1 ? "book" : "books")…")
        }
        return parts.joined(separator: " · ")
    }

    private var audioOffMessage: String {
        var message = "New books’ audio stays on this device. Audio already in iCloud can stay, or be removed from iCloud on all your devices. Books stay in your library either way."
        if cloudOnlyStoredCount > 0 {
            message += " \(cloudOnlyStoredCount == 1 ? "1 book isn’t" : "\(cloudOnlyStoredCount) books aren’t") downloaded on this iPhone. Removing \(cloudOnlyStoredCount == 1 ? "its" : "their") audio leaves Locate… as the only way back unless another device has it."
        }
        return message
    }

    private var relaunchMessage: String {
        if iCloudSyncEnabled {
            return "Quit and reopen Unpaged to finish turning on iCloud sync. Your library will appear shortly after."
        }
        return "Quit and reopen Unpaged to finish turning off iCloud sync. This launch keeps using its current iCloud state."
    }

    // MARK: - Counts

    /// Own books downloaded here whose audio iCloud doesn't fully hold yet.
    private var booksToStore: [Audiobook] {
        books.filter {
            CloudAudioStore.isEligible($0) && $0.isDownloaded && audioStore.state(for: $0) != .stored
        }
    }

    private var booksToStoreBytes: Int64 {
        booksToStore.reduce(0) { $0 + Int64(LibraryImportService.folderSizeMB(for: $1) ?? 0) * 1_048_576 }
    }

    private var uploadingCount: Int {
        books.filter { if case .uploading = audioStore.state(for: $0) { true } else { false } }.count
    }

    private var quotaExceededCount: Int {
        books.filter { audioStore.state(for: $0) == .quotaExceeded }.count
    }

    private var cloudOnlyStoredCount: Int {
        books.filter { $0.isCloudOnlyOrphan && audioStore.state(for: $0) != .none }.count
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Inline, dismissible report of the last cloud-audio failure.
struct CloudAudioErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismiss)
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(SettingsDesign.systemBlue)
        }
    }
}

#Preview {
    NavigationStack {
        ICloudSettingsView()
    }
}

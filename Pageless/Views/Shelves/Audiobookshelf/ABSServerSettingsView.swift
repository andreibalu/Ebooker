//
//  ABSServerSettingsView.swift
//  Pageless
//
//  Settings → Audiobookshelf Server: connection summary, "Open in Shelves", and Disconnect.
//

import SwiftUI

struct ABSServerSettingsView: View {
    var onDismissSheet: () -> Void = {}
    var onOpenInShelves: () -> Void = {}
    var account: ABSAccount = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var isConnectPresented = false
    @State private var isDisconnectConfirming = false
    @State private var isRemoveDownloadsConfirming = false
    @State private var downloadManager = ABSDownloadManager.shared
    @State private var downloadedBytes: Int64 = 0
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            SettingsSheetHeader(
                title: "Audiobookshelf",
                titleStyle: .subview,
                backLabel: "Settings",
                onBack: { dismiss() },
                onDone: onDismissSheet
            )
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let summary = account.summary {
                        connectedContent(summary)
                    } else {
                        disconnectedContent
                    }
                    storageControls
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .settingsInteractiveBackGesture()
        .sheet(isPresented: $isConnectPresented) {
            ABSConnectView(account: account, initialServer: account.summary?.baseURL.absoluteString ?? "")
        }
        .confirmationDialog(
            "Disconnect from \(account.summary?.host ?? "your server")?",
            isPresented: $isDisconnectConfirming,
            titleVisibility: .visible
        ) {
            Button(downloadedBytes > 0 ? "Keep Downloads and Disconnect" : "Disconnect", role: .destructive) {
                Task { await disconnect(removeDownloads: false) }
            }
            .accessibilityIdentifier("abs.settings.disconnect.confirm")
            if downloadedBytes > 0 {
                Button("Remove Downloads and Disconnect", role: .destructive) {
                    Task { await disconnect(removeDownloads: true) }
                }
                .accessibilityIdentifier("abs.settings.disconnect.removeDownloads")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unpaged forgets this login. Kept downloads still play offline. Streaming books need you to connect again.")
        }
        .confirmationDialog("Remove all Audiobookshelf downloads?", isPresented: $isRemoveDownloadsConfirming, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) {
                Task {
                    if let book = player.currentAudiobook, book.isAudiobookshelfBook { player.unloadIfCurrent(book) }
                    await downloadManager.removeAllDownloads()
                    downloadedBytes = downloadManager.downloadedBytes()
                }
            }
            .accessibilityIdentifier("abs.settings.removeDownloads.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your books, progress, moments, and EQ stay in Unpaged. Audio will stream from your server.")
        }
        .task { downloadedBytes = downloadManager.downloadedBytes() }
        .accessibilityIdentifier("abs.settings")
    }

    private var storageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloaded audio: \(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file))")
                .font(.subheadline)
                .accessibilityIdentifier("abs.settings.downloadSize")
            Button("Remove All Downloads", role: .destructive) { isRemoveDownloadsConfirming = true }
                .disabled(downloadedBytes == 0 && downloadManager.jobs.isEmpty)
                .accessibilityIdentifier("abs.settings.removeDownloads")
            if let error = downloadManager.storageError {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("abs.settings.storageError")
            }
        }
        .padding(16)
    }

    private func disconnect(removeDownloads: Bool) async {
        if removeDownloads {
            if let book = player.currentAudiobook, book.isAudiobookshelfBook { player.unloadIfCurrent(book) }
            await downloadManager.removeAllDownloads()
        } else {
            for id in Array(downloadManager.jobs.keys) { await downloadManager.cancel(id) }
        }
        account.disconnect()
        ABSCoverStore.shared.removeAll()
        downloadedBytes = downloadManager.downloadedBytes()
    }

    // MARK: - Connected

    private func connectedContent(_ summary: ABSAccount.Summary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ABSEyebrow(text: "Connected")
                        Text(summary.host)
                            .font(ABSType.headline())
                            .lineLimit(2)
                            .accessibilityIdentifier("abs.settings.host")
                    }
                    .padding(16)

                    SettingsHairline()
                    detailRow("Server", summary.baseURL.absoluteString)
                    SettingsHairline()
                    detailRow("Signed in as", summary.username ?? "—")
                    SettingsHairline()
                    detailRow("Method", summary.usesAPIKey ? "API key" : "Username & password")
                }
            }

            Button {
                onOpenInShelves()
            } label: {
                Text("Open in Shelves")
            }
            .buttonStyle(ABSPrimaryButtonStyle())
            .accessibilityIdentifier("abs.settings.openInShelves")

            Button(role: .destructive) {
                isDisconnectConfirming = true
            } label: {
                Text("Disconnect")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("abs.settings.disconnect")

            footnote
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(SettingsDesign.secondaryLabel)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Not connected

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
                VStack(alignment: .leading, spacing: 8) {
                    ABSEyebrow(text: "Not connected")
                    Text("Bring your own shelf.")
                        .font(ABSType.headline())
                    Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.")
                        .font(.subheadline)
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Connect a Server") { isConnectPresented = true }
                .buttonStyle(ABSPrimaryButtonStyle())
                .accessibilityIdentifier("abs.settings.connect")

            footnote
        }
    }

    private var footnote: some View {
        Text("Your login stays on this iPhone, in the Keychain. Audio streams or downloads straight from your server. Unpaged sends your listening position back to it.")
            .font(.footnote)
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

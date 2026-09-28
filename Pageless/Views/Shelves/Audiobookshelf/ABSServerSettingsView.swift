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
            Button("Disconnect", role: .destructive) {
                account.disconnect()
                ABSCoverStore.shared.removeAll()
            }
            .accessibilityIdentifier("abs.settings.disconnect.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unpaged forgets this login. Books you added stay in your Library, but won't play until you connect again.")
        }
        .accessibilityIdentifier("abs.settings")
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
        Text("Your login stays on this iPhone, in the Keychain. Books stream straight from your server; Unpaged sends your listening position back to it.")
            .font(.footnote)
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

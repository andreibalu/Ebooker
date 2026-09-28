//
//  ICloudSettingsView.swift
//  Pageless
//

import SwiftUI

struct ICloudSettingsView: View {
    /// Closure passed down from `SettingsView` so the Done pill dismisses the entire sheet.
    var onDismissSheet: () -> Void = {}
    /// Returns to the Settings root, where the Unpaged Plus card is shown.
    var onShowPlusCard: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore

    @AppStorage(IcloudSyncGate.preferenceKey) private var iCloudSyncEnabled = false

    @State private var hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()
    @State private var showRelaunchAlert = false

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

                    if plusEntitlement.isPlus {
                        manageCard
                    } else {
                        plusLinkCard
                    }

                    Text("iCloud Sync uses your private iCloud account. Audio files remain on each device. Subscription plans and billing are shown in Unpaged Plus settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
                        .lineSpacing(1)

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
            await plusEntitlement.refreshEntitlements()
            hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()
        }
        .alert("Relaunch Required", isPresented: $showRelaunchAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(relaunchMessage)
        }
    }

    private var featureCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keep titles, progress, moments, recaps and listening history in sync across your devices through your private iCloud account. Audio files stay on each device.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1.5)

                VStack(alignment: .leading, spacing: 8) {
                    featureBullet("All your titles")
                    featureBullet("Progress and bookmarks")
                    featureBullet("Saved moments and recaps")
                    featureBullet("EQ and playback preferences")
                }

                if plusEntitlement.isPlus {
                    subscriptionActiveRow
                } else {
                    Text("iCloud Sync is included with Unpaged Plus.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsDesign.secondaryLabel)
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

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    private var subscriptionActiveRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(SettingsDesign.systemGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Included with Unpaged Plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Turn on sync below when you're ready")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            SettingsDesign.systemGreen.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var plusLinkCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unpaged Plus includes iCloud Sync across your devices.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                SettingsTextLinkButton(title: "View Unpaged Plus") {
                    onShowPlusCard()
                }
            }
            .padding(12)
        }
    }

    private var manageCard: some View {
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
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                SettingsHairline().padding(.leading, 4)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack(spacing: 12) {
                        SettingsRowLabel(
                            title: "Manage Subscription",
                            caption: "Manage or cancel through your Apple ID"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SettingsDesign.tertiaryLabel)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
    }

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

    private var relaunchMessage: String {
        if iCloudSyncEnabled {
            return "Quit and reopen Unpaged to finish turning on iCloud sync. Your library will appear shortly after."
        }
        return "Quit and reopen Unpaged to finish turning off iCloud sync. This launch keeps using its current iCloud state."
    }
}

#Preview {
    NavigationStack {
        ICloudSettingsView()
            .environmentObject(PlusEntitlementStore.shared)
    }
}

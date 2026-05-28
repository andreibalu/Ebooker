//
//  ICloudSettingsView.swift
//  Pageless
//

import StoreKit
import SwiftUI

struct ICloudSettingsView: View {
    /// Closure passed down from `SettingsView` so the "Done" pill in the header
    /// can dismiss the entire sheet (not just pop this pushed view).
    var onDismissSheet: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: ICloudSubscriptionStore

    @AppStorage(IcloudSyncGate.preferenceKey) private var iCloudSyncEnabled = false

    @State private var hasUbiquityIdentity = IcloudSyncGate.hasUbiquityIdentity()
    @State private var showRelaunchAlert = false

    private static let renewDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

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

                    if subscriptionStore.isSubscribed {
                        manageCard
                    }

                    Text("Recurring subscription billed monthly via your Apple ID. Cancel anytime in the App Store subscription settings; access continues through the end of the billing period.")
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
        .task {
            await subscriptionStore.loadProduct()
            await subscriptionStore.refreshEntitlements()
        }
        .alert("Relaunch Required", isPresented: $showRelaunchAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Quit and reopen Unpaged to finish turning on iCloud sync. Your library will appear shortly after.")
        }
        .alert(
            "Purchase",
            isPresented: Binding(
                get: { subscriptionStore.purchaseError != nil },
                set: { if !$0 { subscriptionStore.purchaseError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { subscriptionStore.purchaseError = nil }
        } message: {
            Text(subscriptionStore.purchaseError ?? "")
        }
        .alert(
            "Restore",
            isPresented: Binding(
                get: { subscriptionStore.restoreError != nil },
                set: { if !$0 { subscriptionStore.restoreError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { subscriptionStore.restoreError = nil }
        } message: {
            Text(subscriptionStore.restoreError ?? "")
        }
    }

    // MARK: - Feature card

    private var featureCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keep titles, progress, moments, recaps & listening history in sync across every device \u{2014} privately, through your iCloud account. Audio files stay on each device.")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.secondaryLabel)
                    .lineSpacing(1.5)

                VStack(alignment: .leading, spacing: 8) {
                    featureBullet("All your titles")
                    featureBullet("Progress & bookmarks")
                    featureBullet("Saved moments & recaps")
                    featureBullet("EQ & playback preferences")
                }

                if subscriptionStore.isSubscribed {
                    subscriptionActiveRow
                } else {
                    purchaseBlock
                }
            }
            .padding(16)
        }
    }

    private func featureBullet(_ label: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(SettingsDesign.systemBlue.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(SettingsDesign.systemBlue)
            }
            .frame(width: 18, height: 18)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var purchaseBlock: some View {
        if let loadError = subscriptionStore.loadError {
            Text(loadError)
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }

        SettingsPrimaryButton(
            title: subscriptionStore.introOfferDisplay.map { "Start \($0)" } ?? "Subscribe",
            isLoading: subscriptionStore.isPurchasing,
            isDisabled: subscriptionStore.product == nil
                || subscriptionStore.isLoadingProduct
                || !subscriptionStore.canMakePayments
        ) {
            Task { await subscriptionStore.purchase() }
        }
        .padding(.top, 4)

        Text(subscriptionStore.introOfferDisplay == nil
             ? "\(subscriptionStore.unlockPriceDisplay)/month. Cancel anytime."
             : "Then \(subscriptionStore.unlockPriceDisplay)/month. Cancel anytime.")
            .font(.system(size: 12))
            .foregroundStyle(SettingsDesign.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)

        SettingsTextLinkButton(title: "Restore purchases") {
            Task { await subscriptionStore.restorePurchases() }
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
                Text("Subscription active")
                    .font(.system(size: 14, weight: .semibold))
                Text(activeCaption)
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

    private var activeCaption: String {
        let price = "\(subscriptionStore.unlockPriceDisplay)/month"
        if let renew = subscriptionStore.renewsOn {
            return "\(price) · Renews \(Self.renewDateFormatter.string(from: renew))"
        }
        return price
    }

    // MARK: - Manage card (subscribed only)

    private var manageCard: some View {
        SettingsCard(cornerRadius: SettingsDesign.innerCardCornerRadius) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: Binding(
                    get: { iCloudSyncEnabled && hasUbiquityIdentity },
                    set: { newValue in
                        iCloudSyncEnabled = newValue
                        if newValue {
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
                            title: "Cloud Library",
                            caption: "Restore books that came down from iCloud"
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
                            caption: "Cancel or change plan via Apple ID"
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
        return iCloudSyncEnabled
            ? "On \u{2014} your library syncs across devices"
            : "Off \u{2014} library stays on this device"
    }
}

#Preview {
    NavigationStack {
        ICloudSettingsView()
            .environmentObject(ICloudSubscriptionStore.shared)
    }
}

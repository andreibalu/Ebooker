//
//  PlusHubView.swift
//  Pageless
//
//  The Unpaged Plus hub: the offer and status card, links to the Plus feature settings, and (when
//  sync is on) the iCloud Library. Presented as a sheet from the library header's Plus button, and
//  pushed from Settings' "Unpaged Plus" row. The header button is unconditional, which keeps the
//  iCloud Sync purchase reachable without iCloud sign-in (App Store guideline 3.1.1).
//

import SwiftUI

/// Sheet presented by the library header's Plus button.
struct PlusHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore
    @State private var path: [PlusHubDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            PlusHubScreen(
                onDismissSheet: { dismiss() },
                onAISettings: { path.append(.ai) },
                onICloudSettings: { path.append(.icloud) },
                onCloudLibrary: { path.append(.cloudLibrary) }
            )
            .navigationDestination(for: PlusHubDestination.self) { destination in
                switch destination {
                case .ai:
                    AISettingsView(onDismissSheet: { dismiss() }, onShowPlusCard: { path.removeAll() })
                case .icloud:
                    ICloudSettingsView(onDismissSheet: { dismiss() }, onShowPlusCard: { path.removeAll() })
                case .cloudLibrary:
                    CloudLibraryView()
                }
            }
        }
        .presentationDetents([.large])
        .plusPurchaseErrorAlert(store: plusEntitlement)
    }
}

enum PlusHubDestination: Hashable {
    case ai
    case icloud
    case cloudLibrary
}

/// The hub's content. `backLabel` is set when it is pushed inside another stack (Settings).
struct PlusHubScreen: View {
    var backLabel: String?
    var onDismissSheet: () -> Void
    var onAISettings: () -> Void
    var onICloudSettings: () -> Void
    var onCloudLibrary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var plusEntitlement: PlusEntitlementStore

    private var hideAIEntirely: Bool {
        AppleIntelligenceCapability.availabilityState == .unsupportedDevice
    }

    var body: some View {
        VStack(spacing: 0) {
            if let backLabel {
                SettingsSheetHeader(
                    title: "Membership",
                    titleStyle: .subview,
                    backLabel: backLabel,
                    onBack: { dismiss() },
                    onDone: onDismissSheet
                )
                .padding(.top, 8)
            } else {
                SettingsSheetHeader(title: "Membership", onDone: onDismissSheet)
                    .padding(.top, 6)
            }

            ScrollView {
                VStack(spacing: 22) {
                    UnpagedPlusCard(
                        store: plusEntitlement,
                        includesAI: !hideAIEntirely,
                        onAISettings: onAISettings,
                        onICloudSettings: onICloudSettings
                    )

                    // Only users whose sync store is active this launch have a backed-up library.
                    if IcloudSyncGate.isEnabled() {
                        cloudLibrarySection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color.cream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(InteractiveBackIfPushed(isPushed: backLabel != nil))
        .task {
            await plusEntitlement.refreshEntitlements()
            await plusEntitlement.loadProduct()
        }
    }

    private var cloudLibrarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(eyebrow: "iCloud", title: "Your backed-up library.")

            Button(action: onCloudLibrary) {
                SettingsCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.amber.opacity(0.16))
                            Image(systemName: "icloud")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Color.amber)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        SettingsRowLabel(
                            title: "iCloud Library",
                            caption: "See and manage everything backed up to iCloud"
                        )

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SettingsDesign.tertiaryLabel)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plus.cloudLibrary")
        }
    }
}

private struct InteractiveBackIfPushed: ViewModifier {
    let isPushed: Bool

    func body(content: Content) -> some View {
        if isPushed {
            content.settingsInteractiveBackGesture()
        } else {
            content
        }
    }
}

extension View {
    /// Shows purchase / restore failures from the Plus store as a single "Unpaged Plus" alert.
    /// Attach once per presented surface (the Settings sheet, the Plus hub sheet).
    func plusPurchaseErrorAlert(store: PlusEntitlementStore) -> some View {
        alert(
            "Unpaged Plus",
            isPresented: Binding(
                get: { store.purchaseError != nil || store.restoreError != nil },
                set: {
                    if !$0 {
                        store.purchaseError = nil
                        store.restoreError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                store.purchaseError = nil
                store.restoreError = nil
            }
        } message: {
            Text(store.purchaseError ?? store.restoreError ?? "")
        }
    }
}

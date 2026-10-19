//
//  PlusHubView.swift
//  Pageless
//
//  The Unpaged Plus hub: the offer and status card and a link to the Plus feature settings.
//  Presented as a sheet from the library header's Plus button, and pushed from Settings' "Unpaged
//  Plus" row. The header button is unconditional, which keeps the Plus purchase reachable without
//  iCloud sign-in (App Store guideline 3.1.1). iCloud sync is free and lives in Settings.
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
                onAISettings: { path.append(.ai) }
            )
            .navigationDestination(for: PlusHubDestination.self) { destination in
                switch destination {
                case .ai:
                    AISettingsView(onDismissSheet: { dismiss() }, onShowPlusCard: { path.removeAll() })
                }
            }
        }
        .presentationDetents([.large])
        .plusPurchaseErrorAlert(store: plusEntitlement)
    }
}

enum PlusHubDestination: Hashable {
    case ai
}

/// The hub's content. `backLabel` is set when it is pushed inside another stack (Settings).
struct PlusHubScreen: View {
    var backLabel: String?
    var onDismissSheet: () -> Void
    var onAISettings: () -> Void

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
                        onAISettings: onAISettings
                    )
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

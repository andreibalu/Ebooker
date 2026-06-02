//
//  ICloudBackupBadge.swift
//  Pageless
//

import SwiftUI

/// A subtle "this book is safely backed up to iCloud" affordance.
///
/// It renders **nothing** unless an active iCloud Sync subscription *and* the sync toggle are on
/// (`IcloudSyncGate.isEnabled()`), so it never promises a backup the user isn't actually getting —
/// non-subscribers and sync-off users simply see no badge.
///
/// `NSPersistentCloudKitContainer` exposes no per-object "synced right now" flag, so this is an
/// honest *static* assurance rather than a real-time pulse: when sync is on, every record in the
/// synced store is, by definition, backed up. Use `.overlayIcon` on cover art and `.inlineLabel`
/// in text-dense detail layouts.
struct ICloudBackupBadge: View {
    enum Style {
        /// Compact glyph-in-a-circle for overlaying on cover art (mirrors the favorite-heart chip).
        case overlayIcon
        /// Icon + "Backed up to iCloud" for inline use under metadata.
        case inlineLabel
    }

    var style: Style = .inlineLabel

    var body: some View {
        if IcloudSyncGate.isEnabled() {
            content
                .accessibilityElement()
                .accessibilityLabel("Backed up to iCloud")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .overlayIcon:
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        case .inlineLabel:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud")
                    .font(.system(size: 10, weight: .semibold))
                Text("Backed up to iCloud")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
    }
}

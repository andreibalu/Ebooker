//
//  NetworkMonitor.swift
//  Pageless
//

import Foundation
import Network

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ebooker.networkMonitor")

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-e2e-fixture"),
           !ProcessInfo.processInfo.arguments.contains("-e2e-online") {
            isConnected = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}

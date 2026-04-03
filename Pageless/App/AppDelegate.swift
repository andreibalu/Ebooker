//
//  AppDelegate.swift
//  Pageless
//

import SwiftData
import UIKit

/// Supplies the CarPlay scene configuration alongside SwiftUI `WindowGroup`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var modelContainer: ModelContainer?
    weak var audioPlayer: AudioPlayerManager?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let configuration = UISceneConfiguration(
                name: "CarPlay",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}

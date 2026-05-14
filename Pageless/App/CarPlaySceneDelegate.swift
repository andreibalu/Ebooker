//
//  CarPlaySceneDelegate.swift
//  Pageless
//

import CarPlay
import OSLog
import UIKit

private let carPlayLog = Logger(subsystem: "andreibaludev.Pageless", category: "CarPlay")

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        carPlayLog.info("scene didConnect interfaceController")
        guard let appDelegate = AppDelegate.shared else {
            carPlayLog.error("AppDelegate.shared is nil; aborting CarPlay setup")
            return
        }

        let coord = CarPlayCoordinator(
            modelContainer: appDelegate.modelContainer,
            audioPlayer: appDelegate.audioPlayer,
            freeBookDownloader: appDelegate.freeBookDownloader,
            aiEntitlement: appDelegate.aiEntitlementStore,
            comebackCoordinator: appDelegate.comebackCoordinator
        )
        coordinator = coord
        coord.connect(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlayLog.info("scene didDisconnect")
        coordinator?.disconnect()
        coordinator = nil
    }
}

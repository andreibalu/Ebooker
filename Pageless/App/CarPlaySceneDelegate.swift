//
//  CarPlaySceneDelegate.swift
//  Pageless
//

import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        let coord = CarPlayCoordinator(
            modelContainer: appDelegate.modelContainer,
            audioPlayer: appDelegate.audioPlayer
        )
        coordinator = coord
        coord.connect(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        coordinator?.disconnect()
        coordinator = nil
    }
}

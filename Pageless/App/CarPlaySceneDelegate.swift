//
//  CarPlaySceneDelegate.swift
//  Pageless
//

import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let container = appDelegate.modelContainer,
              let player = appDelegate.audioPlayer
        else { return }

        let coord = CarPlayCoordinator(modelContainer: container, audioPlayer: player)
        coordinator = coord
        coord.connect(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        coordinator?.disconnect()
        coordinator = nil
    }
}

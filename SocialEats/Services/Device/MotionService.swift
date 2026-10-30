//  MotionService.swift

import Foundation
import CoreMotion

protocol MotionServicing: AnyObject {
    var isAvailable: Bool { get }
    var onForceUpdate: ((Double) -> Void)? { get set }
    var onShake: (() -> Void)? { get set }
    func start()
    func stop()
}

final class MotionService: MotionServicing {
    private let manager = CMMotionManager()
    private var detector = ShakeDetector(threshold: 2.5, cooldown: 1.5)
    private let queue = OperationQueue()

    var onForceUpdate: ((Double) -> Void)?
    var onShake: (() -> Void)?

    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50.0
        queue.maxConcurrentOperationCount = 1

        manager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let a = data.acceleration
            let force = ShakeDetector.magnitude(x: a.x, y: a.y, z: a.z)
            let didShake = self.detector.process(x: a.x, y: a.y, z: a.z, timestamp: data.timestamp)

            DispatchQueue.main.async {
                self.onForceUpdate?(force)
                if didShake { self.onShake?() }
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }

    deinit {
        manager.stopAccelerometerUpdates()
    }
}

final class MockMotionService: MotionServicing {
    var isAvailable = true
    var onForceUpdate: ((Double) -> Void)?
    var onShake: (() -> Void)?
    private(set) var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }

    func simulateShake() {
        onForceUpdate?(3.0)
        onShake?()
    }
}

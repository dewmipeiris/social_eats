//
//  MotionService.swift
//  SocialEats
//
//  Core Motion — reads raw accelerometer data from the iPhone hardware
//  (proposal Advanced Feature 2: "Shake to Match", Learning Outcome 4).
//
//  How it works:
//   1. CMMotionManager gives us x, y, z acceleration 50 times a second.
//   2. ShakeDetector (in AppLogic.swift) calculates total force √(x²+y²+z²).
//   3. If force > 2.5g we call `onShake` (and the ViewModel picks a table).
//

import Foundation
import CoreMotion

protocol MotionServicing: AnyObject {
    var isAvailable: Bool { get }
    /// Live force reading in g (used to animate the radar)
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

    /// False on the Simulator (it has no accelerometer)
    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50.0   // 50 readings per second
        queue.maxConcurrentOperationCount = 1

        manager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let a = data.acceleration
            let force = ShakeDetector.magnitude(x: a.x, y: a.y, z: a.z)
            let didShake = self.detector.process(x: a.x, y: a.y, z: a.z, timestamp: data.timestamp)

            // Back to the main thread for UI updates
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

/// Test version — call `simulateShake()` to pretend the phone was shaken.
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

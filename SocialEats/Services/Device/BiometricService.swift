//  BiometricService.swift

import Foundation
import LocalAuthentication

enum BiometricKind {
    case faceID, touchID, opticID, none

    var title: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Passcode"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock"
        }
    }
}

protocol BiometricServicing {
    var availableKind: BiometricKind { get }
    var isSetUp: Bool { get }
    func authenticate(reason: String) async -> Result<Void, BiometricError>
}

enum BiometricError: LocalizedError, Equatable {
    case notAvailable
    case notEnrolled
    case cancelled
    case failed
    case lockedOut

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "his device doesn't support Face ID or Touch ID."
        case .notEnrolled: return "Face ID / Touch ID isn't set up yet. iPhone: Settings → Face ID (or Touch ID) & Passcode. Simulator: menu Features → Face ID → Enrolled."
        case .cancelled: return "Verification was cancelled — your seat was not changed."
        case .failed: return "Face ID / Touch ID didn't recognise you. Please try again."
        case .lockedOut: return "Too many failed attempts. Unlock your phone with your passcode first."
        }
    }
}

final class BiometricService: BiometricServicing {

    var availableKind: BiometricKind {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    var isSetUp: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var checkError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &checkError) else {
            switch LAError.Code(rawValue: checkError?.code ?? 0) {
            case .biometryNotEnrolled: return .failure(.notEnrolled)
            case .biometryLockout: return await authenticateWithPasscode(reason: reason)
            default: return .failure(.notAvailable)
            }
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .success(()) : .failure(.failed)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .failure(.cancelled)
            // "Use Passcode" button, or locked during this attempt -> passcode screen
            case .userFallback, .biometryLockout: return await authenticateWithPasscode(reason: reason)
            default: return .failure(.failed)
            }
        } catch {
            return .failure(.failed)
        }
    }

    private func authenticateWithPasscode(reason: String) async -> Result<Void, BiometricError> {
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                           localizedReason: reason)
            return success ? .success(()) : .failure(.failed)
        } catch let error as LAError where error.code == .userCancel {
            return .failure(.cancelled)
        } catch {
            return .failure(.lockedOut)
        }
    }
}

final class MockBiometricService: BiometricServicing {
    var shouldSucceed: Bool
    var availableKind: BiometricKind = .faceID
    var isSetUp = true
    private(set) var requestCount = 0

    init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        requestCount += 1
        return shouldSucceed ? .success(()) : .failure(.failed)
    }
}

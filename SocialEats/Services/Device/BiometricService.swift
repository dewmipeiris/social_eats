//
//  BiometricService.swift
//  SocialEats
//
//  Face ID / Touch ID using the LocalAuthentication framework
//  (proposal MVP Feature 6). Used to:
//   • confirm a reservation (stops accidental taps and bot RSVPs)
//   • cancel a seat
//   • unlock the app ("Login with Face ID")
//

import Foundation
import LocalAuthentication

/// Which biometric the phone has (for button labels and icons).
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
    /// Shows the Face ID prompt. Returns true if the user passed.
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
        case .notAvailable: return "This device doesn't support Face ID or Touch ID."
        case .notEnrolled: return "Set up Face ID or Touch ID in the Settings app first."
        case .cancelled: return "Verification was cancelled — your seat was not changed."
        case .failed: return "Face ID didn't recognise you. Please try again."
        case .lockedOut: return "Too many failed attempts. Unlock your phone with your passcode first."
        }
    }
}

final class BiometricService: BiometricServicing {

    var availableKind: BiometricKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        // 1. Can this phone do biometrics at all?
        var checkError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &checkError) else {
            switch LAError.Code(rawValue: checkError?.code ?? 0) {
            case .biometryNotEnrolled: return .failure(.notEnrolled)
            case .biometryLockout: return .failure(.lockedOut)
            default: return .failure(.notAvailable)
            }
        }

        // 2. Show the system Face ID / Touch ID prompt
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success ? .success(()) : .failure(.failed)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .failure(.cancelled)
            case .biometryLockout: return .failure(.lockedOut)
            default: return .failure(.failed)
            }
        } catch {
            return .failure(.failed)
        }
    }
}

/// Test / preview version — always succeeds (or always fails).
final class MockBiometricService: BiometricServicing {
    var shouldSucceed: Bool
    var availableKind: BiometricKind = .faceID
    private(set) var requestCount = 0

    init(shouldSucceed: Bool = true) {
        self.shouldSucceed = shouldSucceed
    }

    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        requestCount += 1
        return shouldSucceed ? .success(()) : .failure(.failed)
    }
}

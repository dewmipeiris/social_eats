//
//  FirebaseAuthService.swift
//  SocialEats
//
//  Real sign-in using Firebase Authentication (proposal Feature 1):
//   • Phone number + 6-digit SMS OTP
//   • Google Sign-In (SSO)
//   • Email + password (for the "Phone or Email" field)
//

import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

/// Friendly error messages for sign-in problems.
enum AuthServiceError: LocalizedError {
    case missingGoogleClientID
    case noScreenToPresentOn
    case missingToken
    case cancelled
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .missingGoogleClientID: return "Google Sign-In isn't configured. Check GoogleService-Info.plist."
        case .noScreenToPresentOn: return "Couldn't open the sign-in window. Please try again."
        case .missingToken: return "Sign-in failed — no token was returned."
        case .cancelled: return "Sign-in was cancelled."
        case .wrongPassword: return "That email is already registered and the password is incorrect."
        }
    }
}

final class FirebaseAuthService: AuthServicing {

    // MARK: - Current user

    var currentUserId: String? { Auth.auth().currentUser?.uid }
    var currentDisplayName: String? { Auth.auth().currentUser?.displayName }
    var currentPhone: String? { Auth.auth().currentUser?.phoneNumber }
    var currentEmail: String? { Auth.auth().currentUser?.email }

    // MARK: - Phone OTP

    func sendOTP(to e164Phone: String) async throws -> String {
        do {
            // Firebase sends the SMS and gives back a verification id
            return try await PhoneAuthProvider.provider().verifyPhoneNumber(e164Phone, uiDelegate: nil)
        } catch {
            throw Self.friendly(error)
        }
    }

    func verifyOTP(verificationID: String, code: String) async throws -> String {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            return result.user.uid
        } catch {
            throw Self.friendly(error)
        }
    }

    // MARK: - Google

    @MainActor
    func signInWithGoogle() async throws -> String {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthServiceError.missingGoogleClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = UIApplication.shared.topViewController else {
            throw AuthServiceError.noScreenToPresentOn
        }

        let googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw AuthServiceError.missingToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleResult.user.accessToken.tokenString
        )
        do {
            let result = try await Auth.auth().signIn(with: credential)
            return result.user.uid
        } catch {
            throw Self.friendly(error)
        }
    }

    // MARK: - Email

    func signInWithEmail(_ email: String, password: String) async throws -> String {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return result.user.uid
        } catch {
            // Not found (or hidden by email-enumeration protection) -> try creating the account
            let code = Self.authCode(error)
            guard code == .userNotFound || code == .invalidCredential else {
                throw Self.friendly(error)
            }
            do {
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                return result.user.uid
            } catch {
                let createCode = Self.authCode(error)
                if createCode == .emailAlreadyInUse { throw AuthServiceError.wrongPassword }
                throw Self.friendly(error)
            }
        }
    }

    // MARK: - Sign out

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    // MARK: - Helpers

    /// Reads the Firebase Auth error code from any error (nil if it isn't an Auth error).
    static func authCode(_ error: Error) -> AuthErrorCode? {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else { return nil }
        return AuthErrorCode(rawValue: nsError.code)
    }

    /// Converts Firebase error codes into simple sentences.
    static func friendly(_ error: Error) -> Error {
        guard let code = authCode(error) else { return error }
        let message: String
        switch code {
        case .invalidPhoneNumber: message = "That phone number doesn't look right."
        case .invalidVerificationCode: message = "Wrong code — please check the SMS and try again."
        case .sessionExpired: message = "The code expired. Tap Resend to get a new one."
        case .tooManyRequests: message = "Too many attempts. Please wait a few minutes."
        case .networkError: message = "No internet connection. Please try again."
        case .weakPassword: message = "Password must be at least 6 characters."
        case .invalidEmail: message = "That email address isn't valid."
        default: message = error.localizedDescription
        }
        return NSError(domain: "SocialEatsAuth", code: code.rawValue,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

}

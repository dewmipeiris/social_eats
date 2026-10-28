//
//  AuthViewModel.swift
//  SocialEats
//
//  All sign-in logic for Feature 1 (Authentication & Onboarding):
//   1. User types a phone number -> E.164 smart validation
//   2. Firebase sends a 6-digit SMS code (with a 30 s resend timer)
//   3. User enters the code -> verified -> profile created in Firestore
//  Also: Google, email + password (with Forgot password) and "Login with Face ID".
//  (Sign in with Apple needs a paid Apple Developer account, so it isn't included.)
//

import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {

    enum Step: Equatable {
        case enterDetails     // Figure 2 — Member Sign In
        case enterCode        // Figure 4 — Smart Auth & OTP
    }

    // MARK: - Inputs (bound to text fields)
    @Published var identifierInput = ""      // "Phone or Email" field
    @Published var phoneInput = ""           // "Direct Mobile Access" field
    @Published var country = PhoneNumberValidator.defaultCountry
    @Published var otpCode = "" {
        didSet {
            // Only digits, max 6 — and auto-submit when complete
            let clean = OTPValidator.sanitize(otpCode)
            if clean != otpCode { otpCode = clean }
            if OTPValidator.isComplete(clean), oldValue.count < OTPValidator.codeLength {
                Task { await verifyCode() }
            }
        }
    }
    @Published var emailForPassword = ""
    @Published var password = ""

    // MARK: - Outputs (read by the views)
    @Published private(set) var step: Step = .enterDetails
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var showsPasswordSheet = false
    @Published var resetMessage: String?     // green "check your email" text
    @Published private(set) var resendSecondsLeft = 0
    @Published private(set) var verifiedPhone: String?   // E.164 number the code was sent to

    private let auth: AuthServicing
    private let session: SessionStore
    private var verificationID: String?
    private var timerTask: Task<Void, Never>?

    static let resendDelay = 30

    init(auth: AuthServicing, session: SessionStore) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Validation (drives the green tick + button state)

    var isPhoneValid: Bool {
        PhoneNumberValidator.isValid(phoneInput, country: country)
    }

    var phoneValidationMessage: String? {
        guard !phoneInput.isEmpty, !isPhoneValid else { return nil }
        return "Enter a valid \(country.nationalLength)-digit number"
    }

    var identifierKind: LoginIdentifier {
        LoginIdentifier.detect(identifierInput, country: country)
    }

    var canResend: Bool { resendSecondsLeft == 0 && !isLoading }

    /// "00:28"
    var resendTimerText: String {
        String(format: "00:%02d", resendSecondsLeft)
    }

    var maskedPhone: String {
        verifiedPhone.map(PhoneNumberValidator.masked) ?? ""
    }

    // MARK: - Phone OTP

    /// "Send Login Code" button
    func sendCode() async {
        errorMessage = nil
        guard let e164 = PhoneNumberValidator.toE164(phoneInput, country: country) else {
            errorMessage = "Please enter a valid mobile number, e.g. 77 123 4567."
            Haptics.error()
            return
        }
        await requestCode(for: e164)
    }

    /// "Continue" on the Phone or Email field — works out which one it is.
    func continueWithIdentifier() async {
        errorMessage = nil
        switch identifierKind {
        case .phone(let e164):
            phoneInput = String(e164.dropFirst(country.dialCode.count))
            await requestCode(for: e164)
        case .email(let email):
            emailForPassword = email
            showsPasswordSheet = true
        case .invalid:
            errorMessage = "Enter a valid email address or mobile number."
            Haptics.error()
        }
    }

    func resendCode() async {
        guard canResend, let phone = verifiedPhone else { return }
        otpCode = ""
        await requestCode(for: phone)
    }

    private func requestCode(for e164: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            verificationID = try await auth.sendOTP(to: e164)
            verifiedPhone = e164
            step = .enterCode
            startResendTimer()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    /// "Verify & Continue" (also runs automatically after the 6th digit)
    func verifyCode() async {
        guard !isLoading else { return }
        guard OTPValidator.isComplete(otpCode) else {
            errorMessage = "Enter all 6 digits of the code."
            return
        }
        guard let verificationID else {
            errorMessage = "Please request a new code."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let uid = try await auth.verifyOTP(verificationID: verificationID, code: otpCode)
            Haptics.success()
            await session.finishSignIn(userId: uid)
        } catch {
            errorMessage = error.localizedDescription
            otpCode = ""
            Haptics.error()
        }
        isLoading = false
    }

    /// "Change Phone Number"
    func changePhoneNumber() {
        timerTask?.cancel()
        otpCode = ""
        verificationID = nil
        step = .enterDetails
    }

    private func startResendTimer() {
        timerTask?.cancel()
        resendSecondsLeft = Self.resendDelay
        timerTask = Task { [weak self] in
            while let self, self.resendSecondsLeft > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.resendSecondsLeft -= 1
            }
        }
    }

    // MARK: - Other providers

    func signInWithGoogle() async {
        await runProvider { try await self.auth.signInWithGoogle() }
    }

    func signInWithEmail() async {
        guard EmailValidator.isValid(emailForPassword) else {
            errorMessage = "That email address isn't valid."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        showsPasswordSheet = false
        await runProvider { try await self.auth.signInWithEmail(self.emailForPassword, password: self.password) }
    }

    /// "Forgot password?" on the email sheet
    func forgotPassword() async {
        errorMessage = nil
        resetMessage = nil
        guard EmailValidator.isValid(emailForPassword) else {
            errorMessage = "Type your email address first, then tap Forgot password."
            return
        }
        isLoading = true
        do {
            try await auth.sendPasswordReset(to: emailForPassword)
            resetMessage = "If an account exists for \(emailForPassword), we've sent a link to reset your password. Check your inbox (and Spam)."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// "Login with Face ID" (only works if you've signed in on this phone before)
    func loginWithFaceID() async {
        errorMessage = await session.unlockWithBiometrics()
    }

    private func runProvider(_ signIn: () async throws -> String) async {
        isLoading = true
        errorMessage = nil
        do {
            let uid = try await signIn()
            await session.finishSignIn(userId: uid)
        } catch AuthServiceError.cancelled {
            // User closed the sheet — not an error worth showing
        } catch {
            let nsError = error as NSError
            // Google Sign-In "cancelled" is code -5
            if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
                // ignore
            } else {
                errorMessage = error.localizedDescription
                Haptics.error()
            }
        }
        isLoading = false
    }

    deinit {
        timerTask?.cancel()
    }
}

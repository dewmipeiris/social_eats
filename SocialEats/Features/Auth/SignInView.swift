//
//  SignInView.swift
//  SocialEats
//
//  Prototype Figure 2 (Member Sign In) and Figure 4 (Smart Auth & OTP).
//  One ViewModel drives both steps.
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: AuthViewModel
    private let isDemoMode: Bool

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: AuthViewModel(auth: container.auth, session: container.session))
        isDemoMode = container.isDemoMode
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if isDemoMode {
                        demoNotice
                    }
                    // Errors show at the TOP so they're seen straight away
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    }
                    switch viewModel.step {
                    case .enterDetails:
                        detailsStep
                    case .enterCode:
                        OTPStepView(viewModel: viewModel)
                    }
                }
                .padding(AppLayout.screenPadding)
                .frame(maxWidth: 520)                  // nice width on iPad
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenBackground()
        .animation(.easeInOut(duration: 0.25), value: viewModel.step)
        .sheet(isPresented: $viewModel.showsPasswordSheet) {
            EmailPasswordSheet(viewModel: viewModel)
                // medium = half screen; can be pulled up to full if the messages need more room
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            AppHeader(
                title: viewModel.step == .enterDetails ? "Member Sign In" : "Verify Number",
                showsBack: true,
                onBack: {
                    if viewModel.step == .enterCode {
                        viewModel.changePhoneNumber()
                    } else {
                        session.showOnboarding()
                    }
                }
            )
            Text("Step 2 of 2")
                .font(AppFont.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(Capsule().stroke(AppColors.primary, lineWidth: 1))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.trailing, AppLayout.screenPadding)
        }
    }

    private var demoNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
            Text("Demo mode: any phone number works and any 6-digit code (except 000000) signs you in.")
        }
        .font(AppFont.footnote)
        .foregroundStyle(AppColors.amber)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.amberSoft))
    }

    // MARK: - Step 1: details (Figure 2)

    private var detailsStep: some View {
        VStack(spacing: 16) {
            // Welcome card with Face ID button
            VStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(AppColors.primarySoft))
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(AppColors.amber).frame(width: 12, height: 12)
                    }
                    .accessibilityHidden(true)

                Text("Welcome Back")
                    .font(AppFont.title)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Sign in to access confirmed tables, foodie karma, and dinner squad chats.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await viewModel.loginWithFaceID() }
                } label: {
                    Label("Login with \(session.biometricKind.title)", systemImage: session.biometricKind.systemImage)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColors.faceIDButtonText)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: AppLayout.buttonRadius).fill(AppColors.faceIDButton))
                }
                .disabled(!session.canUseBiometricLogin)
                .opacity(session.canUseBiometricLogin ? 1 : 0.5)
                .accessibilityHint(session.hasSavedAccount
                                   ? "Logs you back in to your saved account"
                                   : "Available after you sign in once on this phone")

                // Small line under the button: tells the user if Face ID login is ready yet
                Label(session.hasSavedAccount
                      ? "Instant Face ID & Touch ID login"
                      : "Sign in once below to turn on Face ID login",
                      systemImage: "checkmark.shield.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .cardStyle(padding: 18)

            // Phone or email + mobile number card
            VStack(alignment: .leading, spacing: 12) {
                Text("Phone or Email")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                HStack(spacing: 8) {
                    Image(systemName: "at")
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("dewmi@example.com or phone", text: $viewModel.identifierInput)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit { Task { await viewModel.continueWithIdentifier() } }
                    if !viewModel.identifierInput.isEmpty {
                        Button {
                            Task { await viewModel.continueWithIdentifier() }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColors.primary)
                        }
                        .accessibilityLabel("Continue")
                    }
                }
                .inputFieldStyle()

                // "— OR WITH ONE-TIME CODE —"
                HStack {
                    Rectangle().fill(AppColors.border).frame(height: 1)
                    OverlineText(text: "or with one-time code")
                        .fixedSize()
                    Rectangle().fill(AppColors.border).frame(height: 1)
                }

                Text("Direct Mobile Access")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 8) {
                    CountryPicker(selection: $viewModel.country)
                    HStack {
                        TextField("77 123 4567", text: $viewModel.phoneInput)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .accessibilityLabel("Mobile number")
                        if viewModel.isPhoneValid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.success)
                                .accessibilityLabel("Valid number")
                        }
                    }
                    .inputFieldStyle()
                }
                if let hint = viewModel.phoneValidationMessage {
                    Text(hint)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.danger)
                }

                LoadingButton(title: "Send Login Code", systemImage: "arrow.right",
                              isLoading: viewModel.isLoading, isEnabled: viewModel.isPhoneValid) {
                    Task { await viewModel.sendCode() }
                }

                Spacer().frame(height: 4)

                Button {
                    Task { await viewModel.signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0x4285F4))
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Continue with Google")
            }
            .cardStyle(padding: 16)

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("New to SocialEats?")
                        .foregroundStyle(AppColors.textSecondary)
                    Button("Create an account") { session.startTasteProfile() }
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.primary)
                }
                .font(AppFont.subheadline)
                Button("Just browsing? Continue as guest") { session.browseAsGuest() }
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(minHeight: AppLayout.minTapTarget)
            }
        }
    }
}

// MARK: - Step 2: OTP (Figure 4)

private struct OTPStepView: View {
    @ObservedObject var viewModel: AuthViewModel
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("SOCIALEATS ACCESS", systemImage: "fork.knife")
                .font(AppFont.overline)
                .foregroundStyle(AppColors.primary)
            Text("Welcome Back, Foodie")
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("Verify your mobile number to reserve tables, share dining moments, and unlock curated food perks.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            // Verified number row
            VStack(alignment: .leading, spacing: 6) {
                Text("Mobile Number")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                HStack {
                    Text("\(viewModel.country.flag) \(viewModel.country.dialCode)")
                        .padding(.trailing, 6)
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(PhoneNumberValidator.formattedForDisplay(viewModel.verifiedPhone ?? "")
                                .replacingOccurrences(of: viewModel.country.dialCode + " ", with: ""))
                            .font(AppFont.headline)
                        Text("Verified carrier network")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.success)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                }
                .inputFieldStyle()
                .accessibilityElement(children: .combine)
            }

            // Code entry card
            VStack(spacing: 14) {
                Image(systemName: "ellipsis.message")
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.primarySoft))
                    .accessibilityHidden(true)
                Text("Enter 6-Digit OTP Code")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Sent via SMS to \(viewModel.maskedPhone)")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)

                OTPBoxesField(code: $viewModel.otpCode, isFocused: $codeFieldFocused)

                if viewModel.canResend {
                    Button("Resend code") { Task { await viewModel.resendCode() } }
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                } else {
                    Label {
                        Text("Resend code in ") + Text(viewModel.resendTimerText).foregroundColor(AppColors.primary).bold()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("You can resend the code in \(viewModel.resendSecondsLeft) seconds")
                }

                Button("Change Phone Number") { viewModel.changePhoneNumber() }
                    .font(AppFont.footnote)
                    .underline()
                    .foregroundStyle(AppColors.primary)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 18)

            LoadingButton(title: "Verify & Continue", systemImage: "arrow.right",
                          isLoading: viewModel.isLoading,
                          isEnabled: OTPValidator.isComplete(viewModel.otpCode)) {
                Task { await viewModel.verifyCode() }
            }

            Text("By continuing, you acknowledge you have read and agreed to SocialEats' Terms of Service and Privacy Policy.")
                .font(AppFont.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .onAppear { codeFieldFocused = true }
    }
}

/// Six boxes that show the code, with one hidden TextField underneath.
/// `.oneTimeCode` lets iOS auto-fill the code from the SMS.
struct OTPBoxesField: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .accessibilityLabel("One-time code")
                .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))

            HStack(spacing: 8) {
                ForEach(0..<OTPValidator.codeLength, id: \.self) { index in
                    let digit = index < code.count ? String(Array(code)[index]) : ""
                    let isCurrent = index == code.count
                    Text(digit)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: 48, minHeight: 52)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppColors.surfaceMuted))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isCurrent ? AppColors.primary : Color.clear, lineWidth: 1.5)
                        )
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }
}

/// Country flag + dial code menu ("🇱🇰 +94 ⌄").
struct CountryPicker: View {
    @Binding var selection: PhoneNumberValidator.Country

    var body: some View {
        Menu {
            ForEach(PhoneNumberValidator.countries) { country in
                Button("\(country.flag) \(country.id) \(country.dialCode)") { selection = country }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.flag)
                Text(selection.dialCode)
                    .foregroundStyle(AppColors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .font(AppFont.body)
            .inputFieldStyle()
        }
        .accessibilityLabel("Country code \(selection.dialCode)")
    }
}

/// Small sheet for the email + password path (with "Forgot password?").
private struct EmailPasswordSheet: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with email")
                .font(AppFont.title)
                .foregroundStyle(AppColors.textPrimary)
            Text("New here? We'll create your account with this password.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColors.textSecondary)
            TextField("Email", text: $viewModel.emailForPassword)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .inputFieldStyle()
            SecureField("Password (6+ characters)", text: $viewModel.password)
                .textContentType(.password)
                .inputFieldStyle()

            // Forgot password link (right side)
            HStack {
                Spacer()
                Button("Forgot password?") {
                    Task { await viewModel.forgotPassword() }
                }
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColors.primary)
                .disabled(viewModel.isLoading)
            }

            // Green message after the reset email is sent
            if let message = viewModel.resetMessage {
                Label(message, systemImage: "envelope.badge")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.success)
            }
            // Red message (e.g. no email typed)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.danger)
            }

            LoadingButton(title: "Continue", isLoading: viewModel.isLoading) {
                Task { await viewModel.signInWithEmail() }
            }
            Spacer()
        }
        .padding(20)
        .screenBackground()
        // Clear old messages each time the sheet opens
        .onAppear {
            viewModel.resetMessage = nil
            viewModel.errorMessage = nil
        }
    }
}

// MARK: - Input field style

extension View {
    /// Peach rounded input box from the prototype.
    func inputFieldStyle() -> some View {
        self
            .font(AppFont.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}

#Preview {
    let container = AppContainer.demo()
    SignInView(container: container)
        .environmentObject(container.session)
}

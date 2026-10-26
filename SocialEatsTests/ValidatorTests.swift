//
//  ValidatorTests.swift
//  SocialEatsTests
//
//  Swift Testing (not XCTest) — checks the "smart validation" used on
//  the sign-in screens: E.164 phone formatting, email, OTP and names.
//

import Testing
@testable import SocialEats

@Suite("Phone number validation (E.164)")
struct PhoneNumberValidatorTests {

    /// Different ways a Sri Lankan user might type the same number
    @Test("Valid Sri Lankan inputs all become +94771234567",
          arguments: ["771234567", "77 123 4567", "0771234567", "077-123-4567", "+94 77 123 4567", "0094771234567"])
    func validSriLankanNumbers(input: String) {
        #expect(PhoneNumberValidator.toE164(input) == "+94771234567")
    }

    @Test("Wrong lengths and foreign codes are rejected",
          arguments: ["", "12345", "7712345678", "+44771234567", "abcdefghi"])
    func invalidNumbers(input: String) {
        #expect(PhoneNumberValidator.toE164(input) == nil)
        #expect(PhoneNumberValidator.isValid(input) == false)
    }

    @Test("UK numbers use the UK country rules")
    func ukNumber() throws {
        let uk = try #require(PhoneNumberValidator.countries.first { $0.id == "GB" })
        #expect(PhoneNumberValidator.toE164("07700 900123", country: uk) == "+447700900123")
    }

    @Test("Display and masked formats")
    func displayFormats() {
        #expect(PhoneNumberValidator.formattedForDisplay("+94771234567") == "+94 77 123 4567")
        #expect(PhoneNumberValidator.masked("+94771234567") == "+94 77 ••• 4567")
    }
}

@Suite("Email, OTP and name validation")
struct OtherValidatorTests {

    @Test(arguments: ["alex@example.com", "dewmi.peiris@nibm.lk", "a.b+c@uni.ac.uk"])
    func validEmails(email: String) {
        #expect(EmailValidator.isValid(email))
    }

    @Test(arguments: ["", "alex", "alex@", "@example.com", "alex@example", "alex example@x.com"])
    func invalidEmails(email: String) {
        #expect(!EmailValidator.isValid(email))
    }

    @Test("OTP keeps only 6 digits")
    func otpSanitize() {
        #expect(OTPValidator.sanitize("12a3-45 6789") == "123456")
        #expect(OTPValidator.isComplete("123456"))
        #expect(!OTPValidator.isComplete("12345"))
        #expect(!OTPValidator.isComplete("12345a"))
    }

    @Test("Names: letters, spaces, apostrophes, 2–40 chars")
    func names() {
        #expect(NameValidator.isValid("Dewmi Peiris"))
        #expect(NameValidator.isValid("O'Neil-Smith"))
        #expect(!NameValidator.isValid("A"))
        #expect(!NameValidator.isValid("R2D2"))
        #expect(!NameValidator.isValid(String(repeating: "a", count: 41)))
    }

    @Test("Phone-or-email field detects which one the user typed")
    func loginIdentifier() {
        #expect(LoginIdentifier.detect("Alex@Example.com") == .email("alex@example.com"))
        #expect(LoginIdentifier.detect("0771234567") == .phone("+94771234567"))
        #expect(LoginIdentifier.detect("hello") == .invalid)
    }
}


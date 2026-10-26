//
//  Validators.swift
//  SocialEats
//
//  "Smart validation" for the sign-in screens.
//  These are plain functions with no UI, so they are easy to unit test.
//

import Foundation

/// Phone number checks and E.164 formatting (proposal Feature 1, step 2).
/// E.164 is the international format Firebase needs, e.g. +94771234567
enum PhoneNumberValidator {

    /// Supported country codes for the country picker.
    struct Country: Identifiable, Hashable {
        let id: String        // ISO code, e.g. "LK"
        let flag: String
        let dialCode: String  // e.g. "+94"
        let nationalLength: Int  // digits after the country code
    }

    static let countries: [Country] = [
        Country(id: "LK", flag: "🇱🇰", dialCode: "+94", nationalLength: 9),
        Country(id: "IN", flag: "🇮🇳", dialCode: "+91", nationalLength: 10),
        Country(id: "GB", flag: "🇬🇧", dialCode: "+44", nationalLength: 10),
        Country(id: "US", flag: "🇺🇸", dialCode: "+1", nationalLength: 10),
        Country(id: "AU", flag: "🇦🇺", dialCode: "+61", nationalLength: 9)
    ]

    static let defaultCountry = countries[0]   // Sri Lanka

    /// Keeps only the digits ("077 123-4567" -> "0771234567").
    static func digitsOnly(_ text: String) -> String {
        text.filter { $0.isNumber }
    }

    /// Turns what the user typed into E.164 format.
    /// Returns nil if the number is the wrong length.
    ///
    /// Examples (Sri Lanka):
    ///   "77 123 4567"  -> "+94771234567"
    ///   "0771234567"   -> "+94771234567"  (leading 0 removed)
    ///   "+94771234567" -> "+94771234567"
    static func toE164(_ input: String, country: Country = defaultCountry) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        var digits = digitsOnly(trimmed)
        let codeDigits = digitsOnly(country.dialCode)

        // User typed the country code themselves (e.g. "+94 77...")
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00") {
            if trimmed.hasPrefix("00") { digits.removeFirst(2) }
            guard digits.hasPrefix(codeDigits) else { return nil }
            digits.removeFirst(codeDigits.count)
        }

        // Local numbers often start with a trunk "0"
        if digits.hasPrefix("0") {
            digits.removeFirst()
        }

        guard digits.count == country.nationalLength else { return nil }
        return "+" + codeDigits + digits
    }

    static func isValid(_ input: String, country: Country = defaultCountry) -> Bool {
        toE164(input, country: country) != nil
    }

    /// Pretty display: "+94 77 123 4567"
    static func formattedForDisplay(_ e164: String) -> String {
        let digits = digitsOnly(e164)
        guard digits.count >= 11 else { return e164 }
        let code = digits.prefix(digits.count - 9)
        let rest = Array(digits.suffix(9))
        let a = String(rest[0..<2]), b = String(rest[2..<5]), c = String(rest[5..<9])
        return "+\(code) \(a) \(b) \(c)"
    }

    /// Masked version for "Sent via SMS to +94 77 ••• 4567"
    static func masked(_ e164: String) -> String {
        let display = formattedForDisplay(e164)
        var parts = display.split(separator: " ").map(String.init)
        if parts.count == 4 { parts[2] = "•••" }
        return parts.joined(separator: " ")
    }
}

/// Email address checks.
enum EmailValidator {
    /// Simple, readable regex: something@something.something
    private static let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#

    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

/// One-time code checks.
enum OTPValidator {
    static let codeLength = 6

    /// Keeps digits only and limits to 6 characters (used while typing).
    static func sanitize(_ text: String) -> String {
        String(text.filter { $0.isNumber }.prefix(codeLength))
    }

    static func isComplete(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { $0.isNumber }
    }
}

/// Display name checks (letters, spaces, apostrophes, hyphens; 2–40 chars).
enum NameValidator {
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (2...40).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'-."))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// Decides whether the "Phone or Email" field holds a phone or an email.
enum LoginIdentifier: Equatable {
    case phone(String)   // already E.164
    case email(String)
    case invalid

    static func detect(_ text: String, country: PhoneNumberValidator.Country = PhoneNumberValidator.defaultCountry) -> LoginIdentifier {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("@") {
            return EmailValidator.isValid(trimmed) ? .email(trimmed.lowercased()) : .invalid
        }
        if let e164 = PhoneNumberValidator.toE164(trimmed, country: country) {
            return .phone(e164)
        }
        return .invalid
    }
}

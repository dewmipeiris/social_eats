//  Validators.swift

import Foundation

enum PhoneNumberValidator {

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
    static func digitsOnly(_ text: String) -> String {
        text.filter { $0.isNumber }
    }

    static func toE164(_ input: String, country: Country = defaultCountry) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        var digits = digitsOnly(trimmed)
        let codeDigits = digitsOnly(country.dialCode)

        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00") {
            if trimmed.hasPrefix("00") { digits.removeFirst(2) }
            guard digits.hasPrefix(codeDigits) else { return nil }
            digits.removeFirst(codeDigits.count)
        }

        if digits.hasPrefix("0") {
            digits.removeFirst()
        }

        guard digits.count == country.nationalLength else { return nil }
        return "+" + codeDigits + digits
    }

    static func isValid(_ input: String, country: Country = defaultCountry) -> Bool {
        toE164(input, country: country) != nil
    }

    static func formattedForDisplay(_ e164: String) -> String {
        let digits = digitsOnly(e164)
        guard digits.count >= 11 else { return e164 }
        let code = digits.prefix(digits.count - 9)
        let rest = Array(digits.suffix(9))
        let a = String(rest[0..<2]), b = String(rest[2..<5]), c = String(rest[5..<9])
        return "+\(code) \(a) \(b) \(c)"
    }

    static func masked(_ e164: String) -> String {
        let display = formattedForDisplay(e164)
        var parts = display.split(separator: " ").map(String.init)
        if parts.count == 4 { parts[2] = "•••" }
        return parts.joined(separator: " ")
    }
}

enum EmailValidator {
    /// Simple, readable regex: something@something.something
    private static let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#

    static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

enum OTPValidator {
    static let codeLength = 6

    static func sanitize(_ text: String) -> String {
        String(text.filter { $0.isNumber }.prefix(codeLength))
    }

    static func isComplete(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy { $0.isNumber }
    }
}

enum NameValidator {
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (2...40).contains(trimmed.count) else { return false }
        let allowed = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'-."))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

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

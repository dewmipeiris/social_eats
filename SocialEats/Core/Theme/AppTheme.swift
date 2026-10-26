//
//  AppTheme.swift
//  SocialEats
//
//  Light / Dark / System appearance options shown in Settings,
//  plus shared spacing and corner-radius values so every screen
//  looks the same.
//

import SwiftUI

/// The three appearance options on the Settings screen.
enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    /// Text shown on the segmented picker
    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// SF Symbol shown next to the title
    var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "iphone"
        }
    }

    /// Value passed to `.preferredColorScheme(...)`.
    /// `nil` means "follow the phone's setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// Shared layout numbers (so we don't hard-code 16 everywhere).
enum AppLayout {
    static let screenPadding: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let buttonRadius: CGFloat = 14
    static let chipRadius: CGFloat = 20
    static let buttonHeight: CGFloat = 52
    /// Apple recommends tap targets of at least 44 x 44 points
    static let minTapTarget: CGFloat = 44
}

/// Text styles used across the app.
/// They are all built from Dynamic Type styles (.title, .body ...),
/// so text grows automatically when the user increases font size.
enum AppFont {
    static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded)
    static let subheadline = Font.system(.subheadline, design: .rounded)
    static let footnote = Font.system(.footnote, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    /// Small all-caps labels such as "APPEARANCE" or "WELCOME BACK"
    static let overline = Font.system(.caption2, design: .rounded).weight(.semibold)
}

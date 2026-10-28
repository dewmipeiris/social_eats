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
/// All fonts in one place. Each one is based on an Apple "text style"
/// (.title, .callout ...) so it still grows/shrinks with the Text Size slider
/// in Settings and with the iPhone's own Dynamic Type setting.
/// (Sizes at the default setting are shown in the comments.)
enum AppFont {
    static let largeTitle = Font.system(.title, design: .rounded).weight(.bold)        // 28 pt – big screen titles
    static let title = Font.system(.title3, design: .rounded).weight(.bold)            // 20 pt – section titles
    static let headline = Font.system(.callout, design: .rounded).weight(.semibold)    // 16 pt – card titles
    static let body = Font.system(.callout, design: .rounded)                          // 16 pt – normal text
    static let callout = Font.system(.subheadline, design: .rounded)                   // 15 pt
    static let subheadline = Font.system(.subheadline, design: .rounded)               // 15 pt
    static let footnote = Font.system(.footnote, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    /// Small all-caps labels such as "APPEARANCE" or "WELCOME BACK"
    static let overline = Font.system(.caption2, design: .rounded).weight(.semibold)
}

/// Text Size slider in Settings > Accessibility (smallest -> biggest).
/// Each step is one of Apple's Dynamic Type sizes, so every screen scales together.
enum AppTextSize: Int, CaseIterable {
    case extraSmall = 0
    case small
    case standard        // the normal size
    case large
    case extraLarge
    case huge

    /// Shown under the slider
    var title: String {
        switch self {
        case .extraSmall: return "Extra Small"
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        case .huge: return "Huge"
        }
    }

    /// The Dynamic Type size applied to the whole app (in RootView)
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall: return .xSmall
        case .small: return .small
        case .standard: return .large          // .large is Apple's normal size
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        case .huge: return .accessibility2
        }
    }
}


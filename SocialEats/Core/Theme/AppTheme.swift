//  AppTheme.swift

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "iphone"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

enum AppLayout {
    static let screenPadding: CGFloat = 16
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let buttonRadius: CGFloat = 14
    static let chipRadius: CGFloat = 20
    static let buttonHeight: CGFloat = 52
    static let minTapTarget: CGFloat = 44
}

enum AppFont {
    static let largeTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let title = Font.system(.title3, design: .rounded).weight(.bold)
    static let headline = Font.system(.callout, design: .rounded).weight(.semibold)
    static let body = Font.system(.callout, design: .rounded)
    static let callout = Font.system(.subheadline, design: .rounded)
    static let subheadline = Font.system(.subheadline, design: .rounded)             
    static let footnote = Font.system(.footnote, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    static let overline = Font.system(.caption2, design: .rounded).weight(.semibold)
}

enum AppTextSize: Int, CaseIterable {
    case extraSmall = 0
    case small
    case standard        // the normal size
    case large
    case extraLarge
    case huge

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

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall: return .xSmall
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        case .huge: return .accessibility2
        }
    }
}


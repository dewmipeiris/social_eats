//
//  AppColors.swift
//  SocialEats
//
//  All the colours used in the app, taken from the Figma prototype.
//  Every colour has a LIGHT and a DARK version, copied from the
//  light-mode and dark-mode screens I submitted:
//    • Light mode = cream background + coral (#FF6A4C) buttons
//    • Dark mode  = near-black background + amber (#FFB84E) buttons
//  The whole app switches automatically when Dark mode is picked in Settings.
//

import SwiftUI
import UIKit

extension Color {

    /// Creates a colour that changes between light and dark mode.
    /// - Parameters:
    ///   - light: hex value used in light mode (e.g. 0xFF6A4C)
    ///   - dark: hex value used in dark mode
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(hex: hex)
        })
    }

    /// Creates a fixed colour from a hex number (same in light and dark).
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    /// Builds a UIColor from a hex number like 0xFF6A4C.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The SocialEats colour palette.
/// Usage example:  Text("Hello").foregroundStyle(AppColors.textPrimary)
enum AppColors {

    // MARK: - Brand
    /// Main accent: coral in light mode, amber in dark mode
    /// (buttons, selected chips, active tab, links)
    static let primary = Color(light: 0xFF6A4C, dark: 0xFFB84E)
    /// Soft version of the accent, behind icons and small badges
    static let primarySoft = Color(light: 0xFFE4DA, dark: 0x3A2C19)
    /// Deeper accent, used for the end of gradients
    static let primaryDeep = Color(light: 0xFF8A3D, dark: 0x9E6925)

    // MARK: - Backgrounds
    /// Whole-screen background (cream / near-black)
    static let background = Color(light: 0xFFF7F5, dark: 0x0D0E13)
    /// Cards, sheets, tab bar
    static let surface = Color(light: 0xFFFFFF, dark: 0x17181D)
    /// Input fields, unselected chips, small panels
    static let surfaceMuted = Color(light: 0xFFF1E8, dark: 0x1E2027)
    /// Thin borders around inputs and cards
    static let border = Color(light: 0xF6DED3, dark: 0x2A2C33)

    // MARK: - Text
    static let textPrimary = Color(light: 0x1E1A18, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x7B706B, dark: 0x9CA0AB)
    static let textTertiary = Color(light: 0xB3A7A1, dark: 0x6B6F7B)
    /// Text/icons ON the accent colour:
    /// white on coral (light mode), near-black on amber (dark mode)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x17181D)

    // MARK: - Status colours
    /// Green for "Seats Filled", toggles and verified ticks
    static let success = Color(light: 0x22B07D, dark: 0x4EDB9C)
    static let successSoft = Color(light: 0xE1F6EC, dark: 0x193A30)
    /// Amber for ratings, karma points and "Optimal" badges
    static let amber = Color(light: 0xF5A021, dark: 0xFFB84E)
    static let amberSoft = Color(light: 0xFFF2DB, dark: 0x3A2C19)
    /// Red/coral for errors, allergies, HOST tags and Log Out
    static let danger = Color(light: 0xE5484D, dark: 0xFB795F)
    static let dangerSoft = Color(light: 0xFDE7E7, dark: 0x34261F)
    /// Green-teal used for vegetarian / vegan chips
    static let teal = Color(light: 0x1C9C8E, dark: 0x5ED3A8)
    static let tealSoft = Color(light: 0xE3F5F2, dark: 0x193A30)

    /// Selected "Halal" chip: orange (light) / coral (dark), as in the prototype
    static let halalChip = Color(light: 0xF5A021, dark: 0xFB795F)

    // MARK: - Special colours
    /// "Login with Face ID" button: black in light mode, dark grey card in dark mode
    static let faceIDButton = Color(light: 0x16120F, dark: 0x262835)
    static let faceIDButtonText = Color(light: 0xFFFFFF, dark: 0xF5F5F7)

    /// My own chat bubbles: coral (light) / dark grey (dark)
    static let myBubble = Color(light: 0xFF6A4C, dark: 0x232531)
    static let myBubbleText = Color(light: 0xFFFFFF, dark: 0xF5F5F7)

    /// "Shake to Match" banner: coral -> orange (light), brown -> amber (dark)
    static let shakeStart = Color(light: 0xFF6A4C, dark: 0x391E03)
    static let shakeEnd = Color(light: 0xFF8A3D, dark: 0xD9953C)

    static let shakeGradient = LinearGradient(
        colors: [shakeStart, shakeEnd],
        startPoint: .leading,
        endPoint: .trailing
    )
}

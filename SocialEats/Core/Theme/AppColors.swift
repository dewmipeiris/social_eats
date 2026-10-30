//  AppColors.swift

import SwiftUI
import UIKit

extension Color {

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(hex: hex)
        })
    }

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum AppColors {

    static let primary = Color(light: 0xFF6A4C, dark: 0xFFB84E)
    static let primarySoft = Color(light: 0xFFE4DA, dark: 0x3A2C19)
    static let primaryDeep = Color(light: 0xFF8A3D, dark: 0x9E6925)
    static let background = Color(light: 0xFFF7F5, dark: 0x0D0E13)
    static let surface = Color(light: 0xFFFFFF, dark: 0x17181D)
    static let surfaceMuted = Color(light: 0xFFF1E8, dark: 0x1E2027)
    static let border = Color(light: 0xF6DED3, dark: 0x2A2C33)
    static let textPrimary = Color(light: 0x1E1A18, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x7B706B, dark: 0x9CA0AB)
    static let textTertiary = Color(light: 0xB3A7A1, dark: 0x6B6F7B)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x17181D)
    static let success = Color(light: 0x22B07D, dark: 0x4EDB9C)
    static let successSoft = Color(light: 0xE1F6EC, dark: 0x193A30)
    static let amber = Color(light: 0xF5A021, dark: 0xFFB84E)
    static let amberSoft = Color(light: 0xFFF2DB, dark: 0x3A2C19)
    static let danger = Color(light: 0xE5484D, dark: 0xFB795F)
    static let dangerSoft = Color(light: 0xFDE7E7, dark: 0x34261F)
    static let teal = Color(light: 0x1C9C8E, dark: 0x5ED3A8)
    static let tealSoft = Color(light: 0xE3F5F2, dark: 0x193A30)
    static let halalChip = Color(light: 0xF5A021, dark: 0xFB795F)
    static let faceIDButton = Color(light: 0x16120F, dark: 0x262835)
    static let faceIDButtonText = Color(light: 0xFFFFFF, dark: 0xF5F5F7)
    static let myBubble = Color(light: 0xFF6A4C, dark: 0x232531)
    static let myBubbleText = Color(light: 0xFFFFFF, dark: 0xF5F5F7)
    static let shakeStart = Color(light: 0xFF6A4C, dark: 0x391E03)
    static let shakeEnd = Color(light: 0xFF8A3D, dark: 0xD9953C)
    static let shakeGradient = LinearGradient(
        colors: [shakeStart, shakeEnd],
        startPoint: .leading,
        endPoint: .trailing
    )
}

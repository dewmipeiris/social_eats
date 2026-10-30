//  SettingsStore.swift

import Foundation
import Combine

final class SettingsStore: ObservableObject {

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "settings.theme"
        static let nearbyAlerts = "settings.nearbyAlerts"
        static let radius = "settings.radiusKm"
        static let faceIDProtection = "settings.faceIDProtection"
        static let meetupReminders = "settings.meetupReminders"
        static let dietary = "settings.dietary"
        static let seenOnboarding = "settings.seenOnboarding"
        static let textSize = "settings.textSize"
        static let haptics = Haptics.enabledKey
    }

    //Light / Dark / System
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    //Nearby Table Alerts toggle
    @Published var nearbyAlertsEnabled: Bool {
        didSet { defaults.set(nearbyAlertsEnabled, forKey: Key.nearbyAlerts) }
    }

    //Proximity Radius slider: 0.5 km (walking) ... 5.0 km (drive)
    @Published var proximityRadiusKm: Double {
        didSet { defaults.set(proximityRadiusKm, forKey: Key.radius) }
    }

    //Face ID Protection toggle — locks the app and protects seat changes
    @Published var faceIDProtectionEnabled: Bool {
        didSet { defaults.set(faceIDProtectionEnabled, forKey: Key.faceIDProtection) }
    }

    // 1-hour-before meetup reminders
    @Published var meetupRemindersEnabled: Bool {
        didSet { defaults.set(meetupRemindersEnabled, forKey: Key.meetupReminders) }
    }

    // Dietary chips — act as global filters on the Dashboard and Map
    @Published var dietaryTags: [DietaryTag] {
        didSet { defaults.set(dietaryTags.map(\.rawValue), forKey: Key.dietary) }
    }

    // Accessibility option: the Text Size slider (smaller / bigger text everywhere)
    @Published var textSize: AppTextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) }
    }

    // Accessibility option: turn vibration feedback off
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Key.seenOnboarding) }
    }

    static let radiusRange: ClosedRange<Double> = 0.5...5.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        nearbyAlertsEnabled = defaults.object(forKey: Key.nearbyAlerts) as? Bool ?? true
        proximityRadiusKm = defaults.object(forKey: Key.radius) as? Double ?? 1.5
        faceIDProtectionEnabled = defaults.object(forKey: Key.faceIDProtection) as? Bool ?? true
        meetupRemindersEnabled = defaults.object(forKey: Key.meetupReminders) as? Bool ?? true
        dietaryTags = (defaults.stringArray(forKey: Key.dietary) ?? []).compactMap(DietaryTag.init(rawValue:))
        hasSeenOnboarding = defaults.bool(forKey: Key.seenOnboarding)
        textSize = AppTextSize(rawValue: defaults.object(forKey: Key.textSize) as? Int ?? AppTextSize.standard.rawValue) ?? .standard
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
    }

    var radiusLabel: String {
        String(format: "%.1f km", proximityRadiusKm)
    }

    var radiusHint: String {
        switch proximityRadiusKm {
        case ..<1.0: return "Walking"
        case ..<2.5: return "Optimal"
        default: return "Drive"
        }
    }

    func toggleDietary(_ tag: DietaryTag) {
        if let index = dietaryTags.firstIndex(of: tag) {
            dietaryTags.remove(at: index)
        } else {
            dietaryTags.append(tag)
        }
    }

    func makeTextSmaller() {
        if let smaller = AppTextSize(rawValue: textSize.rawValue - 1) { textSize = smaller }
    }

    func makeTextBigger() {
        if let bigger = AppTextSize(rawValue: textSize.rawValue + 1) { textSize = bigger }
    }

    func resetForSignOut() {
        dietaryTags = []
    }
}


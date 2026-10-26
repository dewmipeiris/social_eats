//
//  UIHelpers.swift
//  SocialEats
//
//  Small helpers used by views: date text, haptic feedback,
//  QR code images and a "device was shaken" fallback for the Simulator.
//

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - Dates

extension Date {
    /// "Today, 7:00 PM" / "Tomorrow, 1:15 PM" / "Fri 24 Oct, 7:30 PM"
    var friendlyDayTime: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return "Today, \(time)" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow, \(time)" }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }

    /// "7:05 PM"
    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    /// "2h ago", "Just now"
    var relativeText: String {
        if abs(timeIntervalSinceNow) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short label shown on the table card image: "TODAY", "7:30 PM", "SAT"
    var cardBadgeText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return timeIntervalSinceNow < 60 * 60 ? "NOW" : shortTime
        }
        if calendar.isDateInTomorrow(self) { return "TOMORROW" }
        return formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

// MARK: - Haptics

/// Small vibration feedback (e.g. when a shake is detected).
enum Haptics {
    /// Settings > Accessibility > "Vibration Feedback" (on by default)
    static let enabledKey = "settings.haptics"
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .heavy) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - QR code

/// Makes a sharp QR code image from text, fully offline (Core Image).
enum QRCodeGenerator {
    private static let context = CIContext()

    static func image(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        // The raw QR is tiny (about 30x30 px), so scale it up without blurring
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Shake fallback (Simulator: Device > Shake)

extension UIDevice {
    /// Posted when the system detects a shake gesture.
    static let deviceDidShake = Notification.Name("SocialEatsDeviceDidShake")
}

extension UIWindow {
    /// The Simulator has no accelerometer, so we also listen to the
    /// built-in shake gesture (Simulator menu: Device > Shake).
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

struct DeviceShakeModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    func onDeviceShake(perform action: @escaping () -> Void) -> some View {
        modifier(DeviceShakeModifier(action: action))
    }
}

// MARK: - Reduce Motion aware animation

extension View {
    /// Uses the animation only if the user has NOT turned on Reduce Motion.
    func motionSafeAnimation<V: Equatable>(_ animation: Animation?, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Top view controller (needed by Google Sign-In)

extension UIApplication {
    /// The view controller currently on screen.
    var topViewController: UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

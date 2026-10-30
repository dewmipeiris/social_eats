//  UIHelpers.swift

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// dates

extension Date {
    var friendlyDayTime: String {
        let calendar = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(self) { return "Today, \(time)" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow, \(time)" }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }

    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var relativeText: String {
        if abs(timeIntervalSinceNow) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    var cardBadgeText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return timeIntervalSinceNow < 60 * 60 ? "NOW" : shortTime
        }
        if calendar.isDateInTomorrow(self) { return "TOMORROW" }
        return formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

// haptics

enum Haptics {
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

// qr code

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

extension UIDevice {
    static let deviceDidShake = Notification.Name("SocialEatsDeviceDidShake")
}

extension UIWindow {
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

// motion aware animation

extension View {
    func motionSafeAnimation<V: Equatable>(_ animation: Animation?, value: V, reduceMotion: Bool) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}


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

//
//  CheckInViews.swift
//  SocialEats
//
//  Scanning a guest's pass QR code (proposal Feature 8: "show the QR to the host").
//
//  Two ways to scan:
//   1. iPhone: open the normal CAMERA app and point it at the QR.
//      The QR holds a "socialeats://checkin?t=..." link, so iOS offers
//      "Open in SocialEats" and the app shows the result below.
//   2. Inside the app (host): "Check In a Guest" -> choose a photo / screenshot
//      of the pass -> Apple's Vision framework finds the QR in the picture.
//      This also works on the Simulator, which has no camera.
//
//  The check itself (is the code genuine? does the guest still have the seat?)
//  is in CheckIn.check(...) in AppLogic.swift, and works offline.
//

import SwiftUI
import Combine
import UIKit
import PhotosUI
import Vision

/// A scanned pass waiting to be shown (Identifiable so it can drive a .sheet).
struct ScannedPass: Identifiable, Equatable {
    let id: String      // the text inside the QR
}

// MARK: - Result screen

/// "✓ Guest checked in" / "✗ Not a valid pass"
struct CheckInResultView: View {
    let scannedText: String
    @EnvironmentObject private var tablesStore: TablesStore
    @Environment(\.dismiss) private var dismiss

    private var result: CheckInResult {
        CheckIn.check(scannedText: scannedText, tables: tablesStore.tables)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: isGood ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 72))
                .foregroundStyle(isGood ? AppColors.success : AppColors.danger)
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(AppFont.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .combine)
        .onAppear {
            if isGood { Haptics.success() } else { Haptics.error() }
        }
    }

    private var isGood: Bool {
        switch result {
        case .valid, .validButTableUnknown: return true
        case .seatCancelled, .invalid: return false
        }
    }

    private var title: String {
        switch result {
        case .valid(let guestName, _, _, _, _): return "\(guestName) is checked in"
        case .validButTableUnknown: return "Genuine SocialEats pass"
        case .seatCancelled: return "Seat was cancelled"
        case .invalid: return "Not a valid pass"
        }
    }

    private var message: String {
        switch result {
        case .valid(_, let seat, let tableTitle, let venueName, let startTime):
            return "Seat #\(seat) • \(tableTitle)\n\(venueName) • \(startTime.friendlyDayTime)"
        case .validButTableUnknown(let seat):
            return "Seat #\(seat). The code is genuine, but this table isn't loaded on this phone right now."
        case .seatCancelled(let tableTitle):
            return "This guest cancelled their seat at \(tableTitle)."
        case .invalid:
            return "This QR code isn't a SocialEats dining pass, or it has been changed."
        }
    }
}

// MARK: - Host: "Check In a Guest"

/// Host picks a photo / screenshot of a guest's pass; Vision reads the QR in it.
struct CheckInScannerSheet: View {
    @State private var photoItem: PhotosPickerItem?
    @State private var scanned: ScannedPass?
    @State private var errorMessage: String?
    @State private var isReading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.primary)
                    .accessibilityHidden(true)

                Text("Check in your guests")
                    .font(AppFont.title)
                    .foregroundStyle(AppColors.textPrimary)

                // Way 1: the iPhone Camera app
                Label("On iPhone: open the Camera app and point it at the guest's QR, then tap \"Open in SocialEats\".",
                      systemImage: "camera")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Way 2: a photo or screenshot of the pass (works on the Simulator)
                Label("Or choose a photo / screenshot of their pass:",
                      systemImage: "photo")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(isReading ? "Reading QR…" : "Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isReading)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Check In a Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .screenBackground()
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
            .sheet(item: $scanned) { pass in
                CheckInResultView(scannedText: pass.id)
            }
        }
    }

    /// Loads the chosen picture and asks Vision to find a QR code in it.
    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        errorMessage = nil
        defer {
            isReading = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't open that picture."
            return
        }
        if let text = await QRReader.readQR(in: image) {
            scanned = ScannedPass(id: text)
        } else {
            errorMessage = "No QR code found in that picture. Try a clearer screenshot of the pass."
        }
    }
}

// MARK: - Vision QR reader

enum QRReader {
    /// Finds the first QR code in a picture using Apple's Vision framework (on-device).
    static func readQR(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        // Vision work is slow-ish, so do it off the main thread
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            return request.results?.first?.payloadStringValue
        }.value
    }
}


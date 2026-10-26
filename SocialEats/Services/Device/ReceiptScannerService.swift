//
//  ReceiptScannerService.swift
//  SocialEats
//
//  On-device text recognition with Apple's Vision framework
//  (proposal Advanced Feature 1 — Vision AI Receipt Scanner).
//
//  • VNRecognizeTextRequest runs 100% ON THE PHONE — no cloud AI / LLM,
//    which is exactly what Component 3 requires.
//  • `CameraController` streams live camera frames and runs a FAST text
//    pass every ~0.6 s so the UI can "auto-detect" a receipt.
//  • When the user captures, we run an ACCURATE pass on the best frame.
//

import Foundation
import UIKit
import Vision
import AVFoundation
import CoreImage

// MARK: - Vision text recogniser

enum VisionTextRecognizer {

    /// Runs Vision OCR and returns the text lines from top to bottom.
    /// - Parameter fast: `.fast` for live preview, `.accurate` for the final scan
    static func lines(using handler: VNImageRequestHandler, fast: Bool) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = fast ? 0.02 : 0.0

        try handler.perform([request])

        let fragments = (request.results ?? []).compactMap { observation -> TextFragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextFragment(text: text, box: observation.boundingBox)
        }
        return mergeIntoLines(fragments)
    }

    /// Vision often returns "TOTAL LKR" and "3,575.00" as two separate pieces
    /// even though they sit on the same printed row. This joins pieces whose
    /// vertical centres line up into one line, left to right, top to bottom.
    /// (Vision's coordinates start at the BOTTOM-left, so higher y = higher up.)
    static func mergeIntoLines(_ fragments: [TextFragment]) -> [String] {
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }
        var rows: [[TextFragment]] = []

        for fragment in sorted {
            if let lastRow = rows.last, let first = lastRow.first {
                let tolerance = max(first.box.height, fragment.box.height) * 0.5
                if abs(first.box.midY - fragment.box.midY) <= tolerance {
                    rows[rows.count - 1].append(fragment)
                    continue
                }
            }
            rows.append([fragment])
        }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }
}

/// One piece of text Vision found, with where it was on the image (0...1 coordinates).
struct TextFragment {
    let text: String
    let box: CGRect
}

// MARK: - Still image scanner (used for the final capture and photo library)

protocol ReceiptScanning {
    func recognizeLines(in image: UIImage) async throws -> [String]
}

enum ReceiptScanError: LocalizedError {
    case badImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .badImage: return "Couldn't read that photo. Please try another one."
        case .noTextFound: return "No text found. Hold the receipt flat and well lit."
        }
    }
}

final class VisionReceiptScanner: ReceiptScanning {

    func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ReceiptScanError.badImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        // Heavy work -> background thread
        let lines = try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            return try VisionTextRecognizer.lines(using: handler, fast: false)
        }.value

        guard !lines.isEmpty else { throw ReceiptScanError.noTextFound }
        return lines
    }
}

/// Test version that returns fixed lines.
struct MockReceiptScanner: ReceiptScanning {
    var lines: [String]
    func recognizeLines(in image: UIImage) async throws -> [String] { lines }
}

extension CGImagePropertyOrientation {
    /// Converts UIKit's orientation into the one Vision expects.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Live camera

/// Runs the back camera and does live OCR on the video frames.
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum CameraState: Equatable {
        case idle, running, denied, unavailable
    }

    @Published private(set) var state: CameraState = .idle
    /// Text lines from the latest live frame
    @Published private(set) var liveLines: [String] = []

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "socialeats.camera.session")
    private let visionQueue = DispatchQueue(label: "socialeats.camera.vision")
    private let ciContext = CIContext()

    private var isConfigured = false
    private var isProcessingFrame = false
    private var lastProcessed = Date.distantPast
    /// Most recent frame, kept so "Capture" can scan it accurately
    private var latestBuffer: CVPixelBuffer?

    /// Asks for camera permission, then starts the session.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
        state = .idle
    }

    /// Turns the newest frame into a UIImage for the accurate scan.
    func captureCurrentFrame() -> UIImage? {
        guard let buffer = latestBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        // Back camera frames arrive rotated; .right makes them portrait
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configureSession() else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.isConfigured = true
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)
        return true
    }

    // Called for every camera frame (on visionQueue)
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = pixelBuffer

        // Only analyse ~1.5 frames per second to save battery
        guard !isProcessingFrame, Date().timeIntervalSince(lastProcessed) > 0.6 else { return }
        isProcessingFrame = true
        lastProcessed = Date()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        let lines = (try? VisionTextRecognizer.lines(using: handler, fast: true)) ?? []
        isProcessingFrame = false

        DispatchQueue.main.async { [weak self] in
            self?.liveLines = lines
        }
    }
}

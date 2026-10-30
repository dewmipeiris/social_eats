//  ReceiptScannerService.swift

import Foundation
import UIKit
import Vision
import AVFoundation
import CoreImage


enum VisionTextRecognizer {

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

struct TextFragment {
    let text: String
    let box: CGRect
}

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

        let lines = try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            return try VisionTextRecognizer.lines(using: handler, fast: false)
        }.value

        guard !lines.isEmpty else { throw ReceiptScanError.noTextFound }
        return lines
    }
}

struct MockReceiptScanner: ReceiptScanning {
    var lines: [String]
    func recognizeLines(in image: UIImage) async throws -> [String] { lines }
}

extension CGImagePropertyOrientation {
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

final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum CameraState: Equatable {
        case idle, running, denied, unavailable
    }

    @Published private(set) var state: CameraState = .idle
    @Published private(set) var liveLines: [String] = []

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "socialeats.camera.session")
    private let visionQueue = DispatchQueue(label: "socialeats.camera.vision")
    private let ciContext = CIContext()

    private var isConfigured = false
    private var isProcessingFrame = false
    private var lastProcessed = Date.distantPast
    private var latestBuffer: CVPixelBuffer?

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

    func captureCurrentFrame() -> UIImage? {
        guard let buffer = latestBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
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

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer = pixelBuffer

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

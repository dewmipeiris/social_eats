//
//  SpeechService.swift
//  SocialEats
//
//  On-device voice search with the Speech framework
//  (the "Search & Voice" screen in the prototype).
//  Say "cozy ramen spots nearby" and the search box fills itself in.
//
//  Works on iOS 15+ (iPhone 7) and on the Simulator (uses the Mac's microphone).
//

import Combine
import Foundation
import Speech
import AVFoundation

/// @MainActor = every change happens on the main thread,
/// so the mic button and "Listening…" card update straight away.
@MainActor
final class SpeechService: ObservableObject {

    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // MARK: - Permissions

    /// Asks for Speech Recognition + Microphone permission.
    func requestPermission() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micOK = await Self.requestMicrophone()
        return speechOK && micOK
    }

    /// Microphone permission (the new API is iOS 17+, the old one works on iOS 15/16).
    private static func requestMicrophone() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Start / stop

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil

        guard await requestPermission() else {
            errorMessage = "Allow Microphone and Speech Recognition for SocialEats in the iPhone Settings app to use voice search."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Voice search needs an internet connection right now. Please try again."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // We do NOT force "on-device only": older phones (iPhone 7) and the
            // Simulator can't always do that, so iOS picks the best option itself.
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            // Simulator with no microphone selected gives an empty format
            guard format.sampleRate > 0 else {
                errorMessage = "No microphone found. On the Simulator: menu I/O → Audio Input → choose your Mac's microphone."
                stop()
                return
            }
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            transcript = ""
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                // Speech answers on a background thread -> hop back to the main thread
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.stop() }
                    }
                    if let error {
                        // Only show an error if nothing was heard at all
                        if self.transcript.isEmpty && self.isRecording {
                            let code = (error as NSError).code
                            // 1101 / 1700 = Siri & Dictation is turned off on this iPhone
                            if code == 1101 || code == 1700 {
                                self.errorMessage = "Turn on Dictation: iPhone Settings → General → Keyboard → Enable Dictation, then try again."
                            } else {
                                self.errorMessage = "Didn't catch that (\(error.localizedDescription)). Tap the mic and say \"pizza\"."
                            }
                        }
                        print("🎤 Speech error:", error)
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone. Close other apps using it and try again."
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

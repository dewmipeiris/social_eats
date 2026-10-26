//
//  SpeechService.swift
//  SocialEats
//
//  On-device voice search with the Speech framework
//  (the "Search & Voice" screen in the prototype).
//  Say "cozy ramen spots nearby" and the search box fills itself in.
//

import Foundation
import Speech
import AVFoundation

final class SpeechService: ObservableObject {

    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Asks for microphone + speech permission.
    func requestPermission() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        return speechOK && micOK
    }

    func start() async {
        guard !isRecording else { return }
        guard await requestPermission() else {
            errorMessage = "Allow Microphone and Speech Recognition in Settings to use voice search."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Voice search isn't available right now."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Keep everything on the phone when the device supports it
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            transcript = ""
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self?.stop() }
                    }
                    if error != nil { self?.stop() }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone."
            stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

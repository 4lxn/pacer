import AVFoundation
import Foundation
import Observation
import Speech

/// Tap to talk: live transcript into the Ask field, on-device recognition when the device has
/// it (then audio never leaves the phone). One instance per Ask screen.
@Observable
@MainActor
final class SpeechCapture {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var error: String?
    /// True when recognition can run without the network on this device and language.
    private(set) var onDevice = false

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// Asks for both permissions; false when either is denied.
    func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { error = "Speech recognition is off for Pacer in iOS Settings."; return false }
        guard await AVAudioApplication.requestRecordPermission() else { error = "Microphone access is off for Pacer in iOS Settings."; return false }
        return true
    }

    func start() {
        guard !isRecording, let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
        error = nil
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            onDevice = recognizer.supportsOnDeviceRecognition
            request.requiresOnDeviceRecognition = onDevice
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil, self.isRecording { self.finish() }
                }
            }
            isRecording = true
        } catch {
            self.error = "Couldn't start the microphone."
            finish()
        }
    }

    /// Stops listening; `transcript` keeps the last result.
    func stop() { finish() }

    private func finish() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

import Foundation
import Speech
import AVFoundation
import Observation

/// Wraps SFSpeechRecognizer for one-shot voice capture.
/// Requires Info.plist:
///   - NSMicrophoneUsageDescription
///   - NSSpeechRecognitionUsageDescription
@Observable
final class VoiceService {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finished(String)
        case error(String)
    }

    var state: State = .idle
    var partialTranscript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func start() {
        state = .requestingPermission
        partialTranscript = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch auth {
                case .authorized:
                    self.requestMic()
                case .denied, .restricted, .notDetermined:
                    self.state = .error("Speech recognition not authorized")
                @unknown default:
                    self.state = .error("Unknown speech auth state")
                }
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if case .listening = state {
            state = .finished(partialTranscript)
        }
    }

    // MARK: - Internals

    private func requestMic() {
        #if os(iOS) || targetEnvironment(macCatalyst)
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted { self.beginListening() }
                else { self.state = .error("Microphone not authorized") }
            }
        }
        #else
        // macOS: AVCaptureDevice handles the mic permission prompt.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted { self.beginListening() }
                else { self.state = .error("Microphone not authorized") }
            }
        }
        #endif
    }

    private func beginListening() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            state = .error("Speech recognizer unavailable")
            return
        }
        do {
            // AVAudioSession is iOS / Mac Catalyst only — on native macOS the
            // audio engine doesn't need a session category.
            #if os(iOS) || targetEnvironment(macCatalyst)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true

            let input = audioEngine.inputNode
            let recordingFormat = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            state = .listening
            task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
                guard let self = self else { return }
                if let r = result {
                    DispatchQueue.main.async {
                        self.partialTranscript = r.bestTranscription.formattedString
                        if r.isFinal {
                            self.state = .finished(self.partialTranscript)
                            self.cleanup()
                        }
                    }
                }
                if error != nil {
                    DispatchQueue.main.async {
                        self.state = .error("Recognition error")
                        self.cleanup()
                    }
                }
            }
        } catch {
            state = .error("Audio engine failed: \(error.localizedDescription)")
        }
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request = nil
        task = nil
    }
}

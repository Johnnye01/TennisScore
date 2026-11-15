import AVFoundation
import Foundation

/// Finite English score announcements. A new score supersedes queued old speech.
/// Siri responses are returned as IntentDialog instead of speaking through this
/// service, so a voice command produces one spoken result rather than two.
@MainActor
final class SpeechService: NSObject {
    static let shared = SpeechService()

    var onError: ((String) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)

        do {
            let session = AVAudioSession.sharedInstance()
            // Short score announcements use the ordinary playback route. Do not
            // request a long-form route, continuous recording, or microphone access.
            #if os(watchOS)
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            #else
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            #endif
            try session.setActive(true)
        } catch {
            onError?("无法播放语音；手动记分仍可使用。\(error.localizedDescription)")
            return
        }

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 0.98
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateIfIdle()
    }

    private func deactivateIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                      didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.deactivateIfIdle() }
    }
}

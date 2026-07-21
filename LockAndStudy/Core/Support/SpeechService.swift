import AVFoundation
import Foundation

@MainActor
final class SpeechService {
  private let synthesizer = AVSpeechSynthesizer()
  func speak(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.rate = 0.45
    synthesizer.speak(utterance)
  }
}


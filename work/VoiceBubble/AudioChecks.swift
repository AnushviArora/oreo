import Foundation
import AVFoundation

@main struct AudioChecks {
    static func main() {
        precondition(OreoWake.matches("Hey Oreo!"))
        precondition(OreoWake.matches("Oreo"))
        precondition(!OreoWake.matches("stereo"))
        precondition(!OreoWake.matches("hello there"))
        print("Wake phrase matching checks passed.")
        let pcm = Data([0, 0, 255, 127, 0, 128, 1, 0])
        let wav = VoiceSession.wave(pcm)
        precondition(wav.count == pcm.count + 44)
        precondition(VoiceSession.pcmData(wav) == pcm)
        precondition(VoiceSession.pcmData(Data(wav.dropLast())) == nil)
        precondition(VoiceSession.pcmData(Data()) == nil)
        var padded = wav
        padded.insert(contentsOf: [74,85,78,75,1,0,0,0,42,0], at: 12)
        precondition(VoiceSession.pcmData(padded) == pcm)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let buffer = VoiceSession.pcmBuffer(from: pcm, format: format)
        precondition(buffer?.frameLength == 4)
        precondition(abs((buffer?.floatChannelData?[0][1] ?? 0) - (32_767 / 32_768)) < 0.001)
        print("Audio checks passed: PCM round trip, truncated input, empty input, padded WAV chunks.")
        let session = VoiceSession()
        session.key = "sk-test-secret"
        session.handle(["type": "error", "error": ["code": "invalid_api_key", "message": "Incorrect key sk-test-secret"]])
        precondition(session.key.isEmpty)
        precondition(session.lastError?.contains("sk-test-secret") == false)
        precondition(session.lastError?.contains("API key rejected") == true)
        session.key = "sk-replacement"
        session.handle(["type": "error", "error": ["code": "insufficient_quota", "message": "Quota exceeded"]])
        precondition(session.key == "sk-replacement")
        precondition(session.lastError?.contains("billing") == true)
        session.handle(["type": "response.done", "response": ["status": "failed", "status_details": ["error": ["code": "model_not_found", "message": "Unavailable"]]]])
        precondition(session.lastError?.contains("model is unavailable") == true)
        session.handle(["type": "error", "error": ["code": "invalid_value", "message": "Unsupported audio format"]])
        precondition(session.lastError?.contains("Unsupported audio format") == true)
        print("Error checks passed: rejected-key reset, secret redaction, billing classification, failed-response details, request diagnostics.")

        let suiteName = "OreoChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let memory = OreoMemoryStore(defaults: defaults)
        precondition(memory.list().isEmpty)
        precondition(memory.remember("My favorite coffee is an iced latte").contains("Saved"))
        precondition(memory.remember("my favorite coffee is an iced latte").contains("already"))
        precondition(memory.list().count == 1)
        precondition(memory.promptContext.contains("iced latte"))
        precondition(memory.forget(matching: "coffee").contains("Forgot"))
        precondition(memory.list().isEmpty)
        precondition(OreoMacController.bundleIdentifier(for: "Google Chrome") == "com.google.Chrome")
        precondition(OreoMacController.bundleIdentifier(for: "Definitely Not An App") == nil)
        precondition(OreoMacController.searchURL(for: "sassy cookie")?.absoluteString.contains("sassy%20cookie") == true)
        precondition(OreoMacController.youtubeURL(for: "Blank Space")?.absoluteString.contains("Blank%20Space") == true)
        let sampleYouTube = #"{"videoRenderer":{"videoId":"abcdefghijk"},"duplicate":{"videoRenderer":{"videoId":"abcdefghijk"}},"videoRenderer":{"videoId":"ZYXWVUT9876"}}"#
        precondition(OreoMacController.youtubeVideoIDs(in: sampleYouTube) == ["abcdefghijk", "ZYXWVUT9876"])
        let gmailURL = OreoMacController.gmailComposeURL(recipient: "friend@example.com", subject: "Lunch?", body: "Are you free tomorrow?")?.absoluteString ?? ""
        precondition(gmailURL.contains("friend@example.com"))
        precondition(gmailURL.contains("Lunch?"))
        precondition(gmailURL.contains("Are%20you%20free%20tomorrow?"))
        let executor = OreoToolExecutor(memory: memory)
        precondition(executor.execute(name: "remember_memory", arguments: ["fact": "I like purple"]).contains("Saved"))
        precondition(executor.execute(name: "list_memories", arguments: [:]).contains("purple"))
        var calledTool = false
        let toolSession = VoiceSession()
        toolSession.toolHandler = { name, arguments in
            calledTool = name == "remember_memory" && arguments["fact"] as? String == "Testing"
            return "{\"ok\":true}"
        }
        toolSession.handle(["type": "response.done", "response": ["status": "completed", "output": [["type": "function_call", "name": "remember_memory", "call_id": "call-test", "arguments": "{\"fact\":\"Testing\"}"]]]])
        precondition(calledTool)
        print("Memory and tool checks passed: local save/duplicate/forget, app allowlist, executor, and Realtime tool dispatch.")
    }
}

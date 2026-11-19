import Cocoa
import Speech
import AVFoundation
import Security

struct OreoKey {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.anushvi.oreo", kSecAttrAccount as String: "openai"]
    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var q = query
        q[kSecValueData as String] = data
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

final class OreoWake {
    var heard: (() -> Void)?
    var status: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var renewal: Timer?
    private var generation = UUID()
    static func matches(_ words: String) -> Bool {
        words.lowercased().split(whereSeparator: { !$0.isLetter }).contains("oreo")
    }
    func start() {
        stop()
        let current = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] permission in
            DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                guard permission == .authorized else { self.status?("Enable Speech Recognition for Oreo"); return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    DispatchQueue.main.async {
                        guard self.generation == current else { return }
                        guard allowed else { self.status?("Enable microphone access for Oreo"); return }
                        self.listen(current)
                    }
                }
            }
        }
    }
    private func listen(_ current: UUID) {
        guard let recognizer = recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status?("Local wake word unavailable · click to talk"); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = ["Oreo", "Hey Oreo"]
        self.request = request
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stop(); status?("Microphone unavailable"); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                if let result = result, Self.matches(result.bestTranscription.formattedString) {
                    self.stop(); self.heard?()
                } else if error != nil {
                    self.stop(); self.status?("Wake word paused · choose Listen for Oreo")
                } else if result?.isFinal == true {
                    self.start()
                }
            }
        }
        do {
            try engine.start()
            status?("Oreo · say my name to talk")
            renewal = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in self?.start() }
        } catch { stop(); status?("Wake microphone unavailable · click to talk") }
    }
    func stop() {
        generation = UUID()
        renewal?.invalidate(); renewal = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
    }
}

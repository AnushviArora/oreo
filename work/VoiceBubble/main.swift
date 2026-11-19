import Cocoa
import ServiceManagement

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class BubbleView: NSView {
    var clicked: (() -> Void)?
    var resized: ((CGFloat) -> Void)?
    var dragged = false
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?
    private lazy var mascots: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        for name in ["oreo-mascot", "oreo-listening", "oreo-thinking", "oreo-speaking"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png"), let image = NSImage(contentsOfFile: path) { images[name] = image }
        }
        return images
    }()
    var status = "Click to set up voice" { didSet { needsDisplay = true; toolTip = status } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationPhase += 0.22
            if self.mascotName != "oreo-mascot" { self.needsDisplay = true }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { animationTimer?.invalidate() }
    private var mascotName: String {
        if status.contains("Speaking") { return "oreo-speaking" }
        if status.contains("Thinking") || status.contains("Connecting") { return "oreo-thinking" }
        if status.contains("Listening") || status.hasPrefix("Oreo ·") { return "oreo-listening" }
        return "oreo-mascot"
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        let diameter = max(72, bounds.height - 42)
        let logoRect = NSRect(x: (bounds.width - diameter) / 2, y: 34, width: diameter, height: diameter)
        let circle = NSBezierPath(ovalIn: logoRect)
        NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.90, alpha: 1).setFill()
        circle.fill()
        if let mascot = mascots[mascotName] ?? mascots["oreo-mascot"] {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            let source: NSRect
            if mascotName == "oreo-mascot" {
                source = NSRect(x: mascot.size.width * 0.08, y: mascot.size.height * 0.19, width: mascot.size.width * 0.84, height: mascot.size.height * 0.81)
            } else { source = NSRect(origin: .zero, size: mascot.size) }
            let pulse: CGFloat = mascotName == "oreo-speaking" ? 1 + 0.035 * sin(animationPhase) : 1
            let bob: CGFloat = mascotName == "oreo-thinking" ? 2.5 * sin(animationPhase * 0.65) : 0
            let tilt: CGFloat = mascotName == "oreo-listening" ? 1.5 * sin(animationPhase * 0.45) : 0
            let target = logoRect.insetBy(dx: -2 - diameter * (pulse - 1) / 2, dy: -2 - diameter * (pulse - 1) / 2).offsetBy(dx: tilt, dy: bob)
            mascot.draw(in: target, from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.88, alpha: 0.9).setStroke()
        circle.lineWidth = 3
        circle.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black; shadow.shadowBlurRadius = 4
        (status as NSString).draw(in: NSRect(x: 5, y: 2, width: bounds.width - 10, height: 34), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .shadow: shadow])
    }
    override func mouseDown(with event: NSEvent) {
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        dragged = true
        window?.performDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) { if !dragged { clicked?() } }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0.1 else { return }
        resized?(event.scrollingDeltaY > 0 ? 8 : -8)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSSpeechSynthesizerDelegate {
    var panel: BubblePanel!
    var statusItem: NSStatusItem!
    let speech = NSSpeechSynthesizer()
    let voice = VoiceSession()
    let wake = OreoWake()
    let memory = OreoMemoryStore()
    lazy var tools = OreoToolExecutor(memory: memory)
    let wakePhrases = ["Yes, Anushvi?", "Oreo reporting for duty.", "You called?", "What's the tea, Anushvi?", "Oreo is listening."]
    let greetingPhrases = ["Hey Anushvi, it's Oreo. How has your day been?", "Hi Anushvi. Oreo has entered the chat. How are you?", "Hey Anushvi, what's the vibe today?", "Hi Anushvi. Tell Oreo everything."]
    var greetThenTalk = false
    var lastGreeting = Date.distantPast
    var welcomeTimer: Timer?
    var asleep = false
    var bubble: BubbleView!
    var bubbleDiameter: CGFloat = 108
    weak var activeKeyField: NSSecureTextField?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, shortcut) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSStandardKeyBindingResponding.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: shortcut)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        bubbleDiameter = min(220, max(72, CGFloat(UserDefaults.standard.double(forKey: "OreoBubbleDiameter"))))
        if UserDefaults.standard.object(forKey: "OreoBubbleDiameter") == nil { bubbleDiameter = 108 }
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        let panelSize = sizeForBubble(diameter: bubbleDiameter)
        panel = BubblePanel(contentRect: NSRect(x: frame.maxX-panelSize.width-10, y: frame.minY+100, width: panelSize.width, height: panelSize.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let menu = NSMenu()
        for (title, action) in [("About Oreo", #selector(info)), ("Make bubble larger", #selector(makeLarger)), ("Make bubble smaller", #selector(makeSmaller)), ("Reset bubble size", #selector(resetSize)), ("View Oreo's memories…", #selector(showMemories)), ("Clear Oreo's memories…", #selector(clearMemories)), ("Listen for Oreo", #selector(standby)), ("Enable launch at login", #selector(enableLogin)), ("Change API key…", #selector(setup)), ("Connection details…", #selector(connectionDetails)), ("Disconnect / microphone off", #selector(disconnect)), ("Play sample greeting", #selector(greet)), ("Show bubble", #selector(show)), ("Quit", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let view = BubbleView(frame: NSRect(origin: .zero, size: panelSize))
        view.menu = menu
        view.setAccessibilityLabel("Oreo. Drag to move. Right click for options.")
        panel.contentView = view
        bubble = view
        view.clicked = { [weak self] in self?.talk() }
        view.resized = { [weak self] change in self?.resizeBubble(by: change) }
        voice.changed = { [weak self] status in self?.bubble.status = status }
        voice.contextProvider = { [weak self] in self?.memory.promptContext ?? "Oreo has no saved personal memories yet." }
        voice.toolHandler = { [weak self] name, arguments in self?.tools.execute(name: name, arguments: arguments) ?? "{\"ok\":false,\"message\":\"Oreo's local tools are unavailable.\"}" }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍪"
        statusItem.menu = menu
        speech.delegate = self
        wake.status = { [weak self] text in self?.bubble.status = text }
        wake.heard = { [weak self] in self?.activateOreo() }
        voice.idle = { [weak self] in self?.standby() }
        voice.key = OreoKey.load() ?? ""
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(suspend), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(returned), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(suspend), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(returned), name: NSWorkspace.screensDidWakeNotification, object: nil)
        show()
        enableLogin()
        returned()
    }
    @objc func show() { panel.orderFrontRegardless() }
    func sizeForBubble(diameter: CGFloat) -> NSSize {
        NSSize(width: max(260, diameter + 40), height: diameter + 42)
    }
    func resizeBubble(by change: CGFloat) {
        setBubbleSize(bubbleDiameter + change)
    }
    func setBubbleSize(_ requested: CGFloat) {
        let diameter = min(220, max(72, requested))
        guard diameter != bubbleDiameter else { return }
        bubbleDiameter = diameter
        UserDefaults.standard.set(Double(diameter), forKey: "OreoBubbleDiameter")
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let size = sizeForBubble(diameter: diameter)
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
        bubble.needsDisplay = true
    }
    @objc func makeLarger() { resizeBubble(by: 16) }
    @objc func makeSmaller() { resizeBubble(by: -16) }
    @objc func resetSize() { setBubbleSize(108) }
    @objc func talk() {
        greetThenTalk = false
        speech.stopSpeaking()
        wake.stop()
        if voice.lastError != nil { connectionDetails(); return }
        if voice.key.isEmpty { setup() } else { voice.toggle() }
    }
    @objc func connectionDetails() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = voice.lastError == nil ? "Voice connection" : "Let's fix the voice connection"
        alert.informativeText = voice.lastError ?? (voice.ready ? "Connected and ready." : "Not connected. Enter your API key to connect.")
        alert.addButton(withTitle: "Change API key")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Close")
        switch alert.runModal() {
        case .alertFirstButtonReturn: setup()
        case .alertSecondButtonReturn:
            if voice.key.isEmpty { setup() } else { voice.connect() }
        default: break
        }
    }
    @objc func disconnect() {
        greetThenTalk = false; welcomeTimer?.invalidate()
        wake.stop(); voice.autoStart = false; voice.disconnect(); speech.stopSpeaking()
    }
    @objc func standby() { disconnect(); wake.start() }
    func activateOreo() {
        wake.stop()
        guard !voice.key.isEmpty else { setup(); return }
        greetThenTalk = true
        speech.startSpeaking(wakePhrases.randomElement() ?? "Yes, Anushvi?")
    }
    @objc func enableLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status == .requiresApproval {
                    bubble.status = "Allow Oreo in System Settings · Login Items"
                }
            } catch { bubble.status = "Add Oreo to Login Items in System Settings" }
        }
    }
    @objc func suspend() { asleep = true; disconnect() }
    @objc func returned() {
        asleep = false
        welcomeTimer?.invalidate()
        welcomeTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self = self, !self.asleep, Date().timeIntervalSince(self.lastGreeting) > 60 else { return }
            self.lastGreeting = Date()
            self.greetThenTalk = !self.voice.key.isEmpty
            self.wake.stop()
            self.speech.startSpeaking(self.greetingPhrases.randomElement() ?? "Hey Anushvi, it's Oreo. How has your day been?")
        }
    }
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        guard finishedSpeaking, !asleep else { return }
        if greetThenTalk {
            greetThenTalk = false
            if voice.ready { voice.toggle() }
            else { voice.autoStart = true; voice.connect() }
        } else { wake.start() }
    }
    @objc func setup() {
        wake.stop()
        voice.disconnect()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set or replace your API key"
        alert.informativeText = "Enter your OpenAI API key. It is saved in your macOS Keychain so Oreo can reconnect after login. Voice uses your API billing. Click the bubble once to start a conversation. It sends your turn after a short pause, replies, then listens again. Click to stop; the microphone pauses while it answers. Conversations last only for this connection."
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 32))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 3, width: 350, height: 26))
        field.placeholderString = "OpenAI API key"
        let pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteKey))
        pasteButton.frame = NSRect(x: 355, y: 1, width: 85, height: 30)
        accessory.addSubview(field)
        accessory.addSubview(pasteButton)
        activeKeyField = field
        defer { field.stringValue = ""; activeKeyField = nil }
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Connect"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.stringValue = ""
            guard !key.isEmpty else { bubble.status = "A key is needed to connect"; return }
            guard key.hasPrefix("sk-"), !key.contains(where: { $0.isWhitespace }) else {
                voice.fail("That does not look like an OpenAI secret API key. Copy the complete secret key from the API keys page, then choose Change API key.")
                return
            }
            guard OreoKey.save(key) else {
                voice.fail("Could not save your key in macOS Keychain. Check Keychain access and try again.")
                return
            }
            voice.key = key; voice.autoStart = true; voice.connect()
        }
    }
    @objc func pasteKey() {
        guard let field = activeKeyField else { return }
        guard let value = NSPasteboard.general.string(forType: .string) else { NSSound.beep(); return }
        field.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        field.window?.makeFirstResponder(field)
    }
    @objc func greet() {
        wake.stop()
        greetThenTalk = false
        speech.stopSpeaking()
        speech.startSpeaking(greetingPhrases.randomElement() ?? "Hey Anushvi, it is Oreo. How has your day been?")
    }
    @objc func showMemories() {
        NSApp.activate(ignoringOtherApps: true)
        let facts = memory.list()
        let alert = NSAlert()
        alert.messageText = "Oreo's local memories"
        alert.informativeText = facts.isEmpty ? "Oreo has not saved anything yet. Say something like, ‘Oreo, remember that my favorite coffee is an iced latte.’" : facts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        alert.runModal()
    }
    @objc func clearMemories() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear all Oreo memories?"
        alert.informativeText = "This removes every personal detail Oreo has saved on this Mac."
        alert.addButton(withTitle: "Clear memories")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { memory.clear(); bubble.status = "Oreo's memory is clear" }
    }
    @objc func info() {
        let alert = NSAlert()
        alert.messageText = "Oreo — your desktop voice assistant"
        alert.informativeText = "Drag Oreo anywhere. Scroll over the bubble to resize it. Oreo changes expression while listening, thinking, and speaking. Say ‘remember that…’ to save a personal detail locally. Oreo can open an approved app or set your Mac's volume when you ask. Use the right-click menu to view or clear memories."
        alert.runModal()
    }
    @objc func quit() { disconnect(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

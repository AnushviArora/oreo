import Cocoa

final class OreoMemoryStore {
    private let defaults: UserDefaults
    private let key = "OreoPersonalMemories"
    private let limit = 50

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func list() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    @discardableResult func remember(_ value: String) -> String {
        let fact = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !fact.isEmpty else { return "I need a specific detail to remember." }
        var facts = list()
        if facts.contains(where: { $0.caseInsensitiveCompare(fact) == .orderedSame }) {
            return "I already remember that."
        }
        facts.append(fact)
        if facts.count > limit { facts.removeFirst(facts.count - limit) }
        defaults.set(facts, forKey: key)
        return "Saved to Oreo's local memory: \(fact)"
    }

    @discardableResult func forget(matching query: String) -> String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "Tell me which memory to forget." }
        let old = list()
        let kept = old.filter { !$0.localizedCaseInsensitiveContains(needle) }
        guard kept.count != old.count else { return "I couldn't find a matching memory." }
        defaults.set(kept, forKey: key)
        return "Forgot \(old.count - kept.count) matching local memory item(s)."
    }

    func clear() { defaults.removeObject(forKey: key) }

    var promptContext: String {
        let facts = list()
        guard !facts.isEmpty else { return "Oreo has no saved personal memories yet." }
        return "Oreo's locally saved memories about Anushvi:\n" + facts.map { "- \($0)" }.joined(separator: "\n")
    }
}

enum OreoMacController {
    private static let applications: [String: String] = [
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "music": "com.apple.Music",
        "calendar": "com.apple.iCal",
        "notes": "com.apple.Notes",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "system settings": "com.apple.systempreferences",
        "settings": "com.apple.systempreferences",
        "slack": "com.tinyspeck.slackmacgap",
        "zoom": "us.zoom.xos",
        "word": "com.microsoft.Word",
        "microsoft word": "com.microsoft.Word",
        "excel": "com.microsoft.Excel",
        "microsoft excel": "com.microsoft.Excel",
        "powerpoint": "com.microsoft.Powerpoint",
        "microsoft powerpoint": "com.microsoft.Powerpoint",
        "spotify": "com.spotify.client"
    ]

    static func bundleIdentifier(for application: String) -> String? {
        applications[application.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    static func open(_ application: String) -> String {
        let clean = application.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased() == "gmail" {
            guard let url = URL(string: "https://mail.google.com/mail/u/0/#inbox") else { return "I couldn't open Gmail." }
            guard presentInSafari(url) else { return "I couldn't locate Safari on this Mac." }
            return "Opened Gmail in Safari and brought Safari to the front."
        }
        if clean.lowercased() == "finder" {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
            return "Opened Finder."
        }
        guard let bundleID = bundleIdentifier(for: clean),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "I couldn't find \(clean) on this Mac. Oreo only opens approved apps."
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return "Opened \(clean)."
    }

    @discardableResult private static func presentInSafari(_ url: URL) -> Bool {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: configuration) { application, _ in
            DispatchQueue.main.async {
                application?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }
        return true
    }

    private static func openSafariURL(_ url: URL, success: String, reuseFrontTab: Bool = false) -> String {
        let navigation = reuseFrontTab
            ? "if (count of windows) is 0 then\nmake new document with properties {URL:\"\(appleScriptString(url.absoluteString))\"}\nelse\nset URL of current tab of front window to \"\(appleScriptString(url.absoluteString))\"\nend if"
            : "open location \"\(appleScriptString(url.absoluteString))\""
        let source = """
        tell application "Safari"
            activate
            \(navigation)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error { return "Safari couldn't open that page: \(error[NSAppleScript.errorMessage] ?? "macOS rejected the request")." }
        return success
    }

    static func setVolume(_ requested: Int) -> String {
        let level = min(100, max(0, requested))
        var error: NSDictionary?
        NSAppleScript(source: "set volume output volume \(level)")?.executeAndReturnError(&error)
        if let error = error { return "I couldn't change the volume: \(error[NSAppleScript.errorMessage] ?? "macOS rejected the request")." }
        return "Set the Mac volume to \(level) percent."
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func gmailComposeURL(recipient: String, subject: String, body: String) -> URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/u/0/")
        components?.queryItems = [
            URLQueryItem(name: "view", value: "cm"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "tf", value: "1"),
            URLQueryItem(name: "to", value: recipient),
            URLQueryItem(name: "su", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }

    static func openGmailDraft(recipient: String, subject: String, body: String) -> String {
        guard let composeURL = URL(string: "https://mail.google.com/mail/u/0/#compose"), presentInSafari(composeURL) else {
            return "I couldn't open Gmail Compose in Safari."
        }
        let encode: (String) -> String = { Data($0.utf8).base64EncodedString() }
        let recipient64 = encode(recipient)
        let subject64 = encode(subject)
        let body64 = encode(body)
        let fillJavaScript = """
        (()=>{
          const decode=value=>new TextDecoder().decode(Uint8Array.from(atob(value),character=>character.charCodeAt(0)));
          const subjects=[...document.querySelectorAll('input[name="subjectbox"]')].filter(element=>element.offsetParent!==null);
          const subject=subjects[subjects.length-1];
          if(!subject){const compose=document.querySelector('[gh="cm"],div[role="button"][aria-label*="Compose"]');if(compose&&!window.__oreoComposeClicked){window.__oreoComposeClicked=true;compose.click();}return 'waiting';}
          const container=subject.closest('.M9')||subject.closest('[role="dialog"]')||document;
          const setInput=(element,value)=>{if(!element)return;const prototype=element instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(prototype,'value').set;setter.call(element,value);element.dispatchEvent(new Event('input',{bubbles:true}));element.dispatchEvent(new Event('change',{bubbles:true}));};
          const recipient=decode('\(recipient64)'), subjectText=decode('\(subject64)'), body=decode('\(body64)');
          setInput(subject,subjectText);
          const recipientFields=[...container.querySelectorAll('input[aria-label^="To recipients"],input[aria-label="To"],input[peoplekit-id],input.agP,textarea[name="to"]')].filter(element=>element.offsetParent!==null);
          const to=recipientFields[recipientFields.length-1];
          if(recipient&&!to)return 'waiting';
          if(recipient){setInput(to,recipient);to.focus();to.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));to.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));}
          const editor=container.querySelector('div[aria-label="Message Body"],div[contenteditable="true"][role="textbox"]');
          if(body&&!editor)return 'waiting';
          if(editor){editor.focus();editor.textContent=body;editor.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:body}));}
          return 'filled:'+Boolean(subject)+':'+Boolean(editor);
        })()
        """.replacingOccurrences(of: "\n", with: " ")
        let escapedFill = appleScriptString(fillJavaScript)
        let gmailURL = composeURL.absoluteString
        let source = """
        tell application "Safari"
            activate
            if (count of windows) is 0 then
                make new document with properties {URL:"\(gmailURL)"}
            else if URL of current tab of front window does not contain "mail.google.com" then
                set URL of current tab of front window to "\(gmailURL)"
            end if
            repeat 80 times
                delay 0.25
                try
                    set fillResult to do JavaScript "\(escapedFill)" in current tab of front window
                    if fillResult starts with "filled:" then return fillResult
                end try
            end repeat
            return "timeout"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error = error { return "Gmail opened, but Safari blocked Oreo from filling the draft: \(error[NSAppleScript.errorMessage] ?? "permission is required")." }
        if result?.hasPrefix("filled:") == true { return "Safari is in front, the Gmail compose window is visible, and the current draft fields were filled. The message has not been sent." }
        return "Safari was brought to the front, but Gmail's Compose fields did not appear before Oreo timed out."
    }

    static func youtubeURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components?.url
    }

    static func youtubeVideoIDs(in html: String) -> [String] {
        let pattern = #"\"videoRenderer\":\{\"videoId\":\"([A-Za-z0-9_-]{11})\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let idRange = Range(match.range(at: 1), in: html) else { return nil }
            let id = String(html[idRange])
            return seen.insert(id).inserted ? id : nil
        }
    }

    static func resolveYouTubeVideo(query: String, resultNumber: Int) -> URL? {
        guard let search = youtubeURL(for: query) else { return nil }
        var request = URLRequest(url: search, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("CONSENT=YES+", forHTTPHeaderField: "Cookie")
        let semaphore = DispatchSemaphore(value: 0)
        var result: URL?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data, let html = String(data: data, encoding: .utf8) else { return }
            let ids = youtubeVideoIDs(in: html)
            let index = max(1, resultNumber) - 1
            guard ids.indices.contains(index) else { return }
            result = URL(string: "https://www.youtube.com/watch?v=\(ids[index])")
        }.resume()
        _ = semaphore.wait(timeout: .now() + 13)
        return result
    }

    private static func appleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func searchWeb(_ query: String) -> String {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let url = searchURL(for: clean) else { return "Tell me what to search for." }
        let source = """
        tell application "Safari"
            activate
            open location "\(appleScriptString(url.absoluteString))"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error { return "I couldn't search Safari: \(error[NSAppleScript.errorMessage] ?? "macOS rejected the request")." }
        return "Opened Safari and searched for \(clean)."
    }

    private static func youtubeSelectionJavaScript(_ resultNumber: Int) -> String {
        let index = max(0, resultNumber - 1)
        return """
        (()=>{
          const selectors='ytd-video-renderer a#video-title, ytd-rich-item-renderer a#video-title-link, a#video-title';
          const videos=[...document.querySelectorAll(selectors)].filter((item,position,all)=>item.href&&item.href.includes('/watch')&&all.findIndex(other=>other.href===item.href)===position);
          const chosen=videos[\(index)];
          if(!chosen)return 'waiting';
          const title=(chosen.getAttribute('title')||chosen.textContent||'video').trim();
          window.location.assign(chosen.href);
          return 'opened:'+title;
        })()
        """.replacingOccurrences(of: "\n", with: " ")
    }

    private static func youtubePlaybackJavaScript() -> String {
        """
        (()=>{const video=document.querySelector('video');if(!video)return 'waiting';video.muted=false;video.play().catch(()=>{const button=document.querySelector('.ytp-large-play-button,.ytp-play-button');if(button)button.click()});return 'playing'})()
        """.replacingOccurrences(of: "\n", with: " ")
    }

    private static func openYouTubeVideo(_ url: URL, description: String) -> String {
        let playbackScript = appleScriptString(youtubePlaybackJavaScript())
        let source = """
        tell application "Safari"
            activate
            open location "\(appleScriptString(url.absoluteString))"
            repeat 30 times
                delay 0.25
                try
                    set playbackResult to do JavaScript "\(playbackScript)" in current tab of front window
                    if playbackResult is "playing" then return "playing"
                end try
            end repeat
            return "opened"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error = error {
            return "I opened \(description) on YouTube, but Safari blocked the playback command: \(error[NSAppleScript.errorMessage] ?? "permission is required")."
        }
        return result == "playing" ? "Playing \(description) on YouTube in Safari." : "Opened \(description) directly on YouTube."
    }

    static func playYouTube(_ query: String, resultNumber: Int = 1) -> String {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let url = youtubeURL(for: clean) else { return "Tell me what to play on YouTube." }
        let number = max(1, resultNumber)
        if let directURL = resolveYouTubeVideo(query: clean, resultNumber: number) {
            return openYouTubeVideo(directURL, description: number == 1 ? clean : "result number \(number) for \(clean)")
        }
        let selectionScript = appleScriptString(youtubeSelectionJavaScript(resultNumber))
        let playbackScript = appleScriptString(youtubePlaybackJavaScript())
        let source = """
        tell application "Safari"
            activate
            open location "\(appleScriptString(url.absoluteString))"
            set selectedVideo to "waiting"
            repeat 30 times
                delay 0.5
                try
                    set selectedVideo to do JavaScript "\(selectionScript)" in current tab of front window
                    if selectedVideo starts with "opened:" then exit repeat
                end try
            end repeat
            if selectedVideo starts with "opened:" then
                repeat 20 times
                    delay 0.25
                    try
                        set playbackResult to do JavaScript "\(playbackScript)" in current tab of front window
                        if playbackResult is "playing" then return selectedVideo
                    end try
                end repeat
                return selectedVideo
            end if
            return "results"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error = error {
            return "I opened the YouTube results for \(clean), but Safari blocked automatic playback: \(error[NSAppleScript.errorMessage] ?? "permission is required")."
        }
        if let result = result, result.hasPrefix("opened:") {
            return "Playing \(String(result.dropFirst("opened:".count))) on YouTube in Safari."
        }
        return "I opened YouTube results for \(clean), but I couldn't identify video number \(max(1, resultNumber)) automatically."
    }

    static func playVisibleYouTubeResult(_ resultNumber: Int) -> String {
        let number = max(1, resultNumber)
        let selectionScript = appleScriptString(youtubeSelectionJavaScript(number))
        let playbackScript = appleScriptString(youtubePlaybackJavaScript())
        let source = """
        tell application "Safari"
            activate
            try
                set selectedVideo to do JavaScript "\(selectionScript)" in current tab of front window
                if selectedVideo starts with "opened:" then
                    repeat 20 times
                        delay 0.25
                        try
                            set playbackResult to do JavaScript "\(playbackScript)" in current tab of front window
                            if playbackResult is "playing" then return selectedVideo
                        end try
                    end repeat
                    return selectedVideo
                end if
            end try
            return "missing"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if let error = error { return "Safari blocked that YouTube selection: \(error[NSAppleScript.errorMessage] ?? "permission is required")." }
        if let result = result, result.hasPrefix("opened:") {
            return "Playing \(String(result.dropFirst("opened:".count))) from result number \(number)."
        }
        return "I couldn't find video number \(number) in the visible YouTube results."
    }
}

final class OreoToolExecutor {
    let memory: OreoMemoryStore
    private var lastYouTubeQuery: String?
    private var gmailRecipient = ""
    private var gmailSubject = ""
    private var gmailBody = ""
    init(memory: OreoMemoryStore) { self.memory = memory }

    func execute(name: String, arguments: [String: Any]) -> String {
        let message: String
        switch name {
        case "remember_memory": message = memory.remember(arguments["fact"] as? String ?? "")
        case "forget_memory": message = memory.forget(matching: arguments["query"] as? String ?? "")
        case "list_memories":
            let facts = memory.list()
            message = facts.isEmpty ? "Oreo's local memory is empty." : facts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case "open_application": message = OreoMacController.open(arguments["application"] as? String ?? "")
        case "set_system_volume":
            let level = (arguments["level"] as? NSNumber)?.intValue ?? -1
            message = level < 0 ? "A volume level from 0 to 100 is required." : OreoMacController.setVolume(level)
        case "search_web": message = OreoMacController.searchWeb(arguments["query"] as? String ?? "")
        case "play_youtube":
            let number = (arguments["result_number"] as? NSNumber)?.intValue ?? 1
            let query = arguments["query"] as? String ?? ""
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastYouTubeQuery = query }
            message = OreoMacController.playYouTube(query, resultNumber: number)
        case "play_youtube_result":
            let number = (arguments["result_number"] as? NSNumber)?.intValue ?? 1
            if let query = lastYouTubeQuery {
                message = OreoMacController.playYouTube(query, resultNumber: number)
            } else {
                message = OreoMacController.playVisibleYouTubeResult(number)
            }
        case "update_gmail_draft":
            if let recipient = arguments["recipient"] as? String, !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { gmailRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let subject = arguments["subject"] as? String { gmailSubject = subject }
            if let body = arguments["body"] as? String { gmailBody = body }
            message = OreoMacController.openGmailDraft(recipient: gmailRecipient, subject: gmailSubject, body: gmailBody)
        case "open_gmail_compose":
            message = OreoMacController.openGmailDraft(recipient: gmailRecipient, subject: gmailSubject, body: gmailBody)
        case "clear_gmail_draft":
            gmailRecipient = ""; gmailSubject = ""; gmailBody = ""
            message = "Cleared Oreo's pending Gmail draft details."
        default: message = "Oreo does not support that action."
        }
        let object: [String: Any] = ["ok": !message.lowercased().contains("couldn't"), "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return "{\"ok\":false}" }
        return json
    }
}

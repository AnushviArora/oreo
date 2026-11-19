# Oreo
Built July–September 2026; published to GitHub in November 2026.

**Oreo is a floating, voice-first AI assistant for macOS that can hold natural conversations and perform a limited set of approved desktop actions.**

## What it does

Oreo lives in a transparent, resizable bubble that can launch when the user logs in and greet them when the Mac wakes. The user can click the bubble or say “Oreo” to begin a voice conversation. Oreo records a spoken turn, sends it to OpenAI's Realtime API, streams the spoken response back, and resumes listening automatically.

Oreo can also execute an allowlisted set of local tools. It can open supported applications, change system volume, search Safari, resolve and play YouTube results, and prepare Gmail drafts without sending them. Personal details are saved only after an explicit “remember” request and can be reviewed, forgotten, or cleared locally.

## Key features

- Natural voice conversations using streamed PCM audio over a WebSocket
- Local “Oreo” name detection through Apple's on-device Speech framework
- Animated listening, thinking, and speaking mascot states
- Automatic speech-end detection with quiet-speech and hard-timeout fallbacks
- Resizable, draggable, always-on-top AppKit panel
- Launch-at-login and wake greeting support
- API key storage in macOS Keychain
- Local memory for up to 50 short details using `UserDefaults`
- Allowlisted function tools for supported Mac, Safari, YouTube, and Gmail actions
- Temporary audio-file deletion after sending or disconnecting

## Response latency

The original request/response path felt like **6+ seconds** because playback waited too long before the user heard the answer. Oreo now starts playing response audio as chunks arrive instead of waiting for the complete response. Together with minimal reasoning for casual requests and turn submission after roughly 0.75 seconds of silence, this reduced observed response time to **about 3 seconds** in normal use.

Quiet phrases receive an additional level-based fallback, and a four-second hard cutoff prevents the interface from remaining on “Listening” when macOS reports unusable microphone levels.

## Tech stack

- **Swift**
- **AppKit / Cocoa** for the floating macOS interface
- **AVFoundation** for recording and streamed audio playback
- **Speech** for local name detection
- **OpenAI Realtime API** over `URLSessionWebSocketTask`
- **macOS Keychain Services** for API-key storage
- **ServiceManagement** for launch-at-login registration
- **AppleScript and browser JavaScript** for constrained Safari, YouTube, and Gmail automation
- **UserDefaults** for bubble preferences and local memories

## Build and run

### Requirements

- macOS 13 or later
- Apple's Swift command-line tools (`xcode-select --install`)
- An OpenAI API account with billing and Realtime API access

### API-key placeholder

Use your own secret key when Oreo prompts on first launch:

```text
[YOUR_OPENAI_API_KEY]
```

Do not place a real key in source code, a plist, an xcconfig file, or Git. Oreo saves the entered key in macOS Keychain and reads it from there on later launches.

### Build

```bash
git clone https://github.com/AnushviArora/oreo.git
cd oreo
sh work/VoiceBubble/build.sh
open outputs/Oreo.app
```

On first launch, allow the requested Microphone and Speech Recognition permissions. Safari and Gmail actions may also require macOS Automation permission. If launch-at-login requires approval, enable Oreo under **System Settings → General → Login Items**.

Run the local checks with:

```bash
swiftc -parse-as-library \
  -module-cache-path /private/tmp/voicebubble-module-cache \
  work/VoiceBubble/AudioChecks.swift \
  work/VoiceBubble/VoiceSession.swift \
  work/VoiceBubble/OreoFeatures.swift \
  work/VoiceBubble/OreoTools.swift \
  -o /private/tmp/OreoChecks \
  -framework Cocoa -framework AVFoundation -framework Speech -framework Security

/private/tmp/OreoChecks
```

## Known limits

- Oreo is a personal macOS prototype and is ad-hoc signed by the build script rather than distributed through the Mac App Store.
- The local name detector is not speaker identification; anyone saying “Oreo” may activate it.
- The microphone pauses while Oreo speaks, so users cannot interrupt a response mid-sentence.
- Browser automation depends on Safari permissions and page structure and may break when websites change.
- Gmail support prepares and fills drafts but deliberately does not press **Send**.
- YouTube selection depends on the ordering returned by YouTube search.
- Memories are stored locally in `UserDefaults`, are not encrypted, and are injected only when a new Realtime session starts.
- Voice conversations require paid OpenAI API credits and internet access.

## Project structure

```text
work/VoiceBubble/
├── main.swift          # App lifecycle, floating bubble, menus and greetings
├── VoiceSession.swift  # Realtime WebSocket, recording and streamed playback
├── OreoFeatures.swift  # Keychain storage and local name detection
├── OreoTools.swift     # Memory and allowlisted desktop/browser tools
├── AudioChecks.swift   # Local behavior checks
├── Info.plist          # macOS bundle metadata and permission descriptions
├── build.sh            # Command-line app-bundle build
└── Assets/             # Oreo mascot states
```

#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
mkdir -p outputs/Oreo.app/Contents/MacOS outputs/Oreo.app/Contents/Resources
cp work/VoiceBubble/Info.plist outputs/Oreo.app/Contents/Info.plist
cp work/VoiceBubble/Assets/oreo-mascot.png outputs/Oreo.app/Contents/Resources/oreo-mascot.png
cp work/VoiceBubble/Assets/oreo-listening.png outputs/Oreo.app/Contents/Resources/oreo-listening.png
cp work/VoiceBubble/Assets/oreo-thinking.png outputs/Oreo.app/Contents/Resources/oreo-thinking.png
cp work/VoiceBubble/Assets/oreo-speaking.png outputs/Oreo.app/Contents/Resources/oreo-speaking.png
swiftc -module-cache-path /private/tmp/voicebubble-module-cache work/VoiceBubble/main.swift work/VoiceBubble/VoiceSession.swift work/VoiceBubble/OreoFeatures.swift work/VoiceBubble/OreoTools.swift -o outputs/Oreo.app/Contents/MacOS/VoiceBubble -framework Cocoa -framework AVFoundation -framework Speech -framework Security -framework ServiceManagement
codesign --force --sign - outputs/Oreo.app
plutil -lint outputs/Oreo.app/Contents/Info.plist

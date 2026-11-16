# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SayIt is a macOS menu-bar voice input app (LSUIElement, no dock icon). It records speech, transcribes via multiple STT engines, optionally optimizes text through LLM, and pastes into the active app. UI and debug logs are primarily in Chinese.

## Build

```bash
# Generate Xcode project (after editing project.yml)
xcodegen generate

# Build
xcodebuild -project SayIt.xcodeproj -scheme SayIt -configuration Debug build

# Run tests
xcodebuild test -project SayIt.xcodeproj -scheme SayIt
```

No SPM/Package.swift — whisper.cpp is vendored at `vendor/whisper.cpp/` and linked as a pre-built static library (`libwhisper_all`). Deployment target: macOS 12.0, Swift 5.9.

## Architecture

**AppDelegate** (`AppDelegate.swift`, ~530 lines) is the central orchestrator. It owns all major components and coordinates the recording lifecycle. Key flow:

1. `HotkeyManager` detects modifier key tap (Fn/⌘/⌥/⌃) via `CGEventTap`
2. `AudioRecorder` captures audio via `AVAudioEngine`, emits buffer snapshots and level callbacks
3. STT dispatch by engine (`handleRecordingStop`):
   - **Local Whisper**: streaming transcription via timer + final from PCM buffer
   - **Deepgram**: WebSocket streaming during recording
   - **OpenAI Whisper**: full audio upload after recording stops
4. Post-processing: voice commands → snippet expansion → optional LLM optimization
5. Output: clipboard + simulated Cmd+V paste

**Singleton pattern** throughout — `WhisperTranscriber.shared`, `TextOptimizer.shared`, `HistoryManager.shared`, etc.

**TranscriptionService protocol** (`Controllers/TranscriptionService.swift`) abstracts STT engines with `prepare()`, `transcribe()`, `transcribeBuffer()`.

**SwiftUI + AppKit hybrid**: SwiftUI views (`OverlayView`, `SettingsView`, `HistoryView`) hosted in AppKit `NSWindowController` via `NSHostingView`. `OverlayViewModel` drives overlay UI via `@Published` properties.

**Persistence**: UserDefaults for settings (string keys like `sttEngine`, `speechLanguage`, `triggerKey`). JSON files in `~/Library/Application Support/SayIt/` for history, snippets, user dictionary, and user rules.

**C++ bridge**: `WhisperBridge/whisper_wrapper.cpp` wraps whisper.cpp C API, exposed to Swift via `SayIt-Bridging-Header.h`.

## External APIs

- Deepgram Nova-3 (WebSocket streaming + REST)
- OpenAI Whisper API (multipart form upload)
- DeepSeek Chat API (text optimization, OpenAI-compatible)
- Google Gemini API (text optimization, OpenAI-compatible)

API keys stored in UserDefaults, configured in Settings UI.

## Branch Management Workflow

需求条目记录在 `feat_list.md`（格式：需求编号、版本号、需求内容、测试用例）。

开发流程：
1. 从 `master` 创建特性分支，命名 `FEAT-版本名`（如 `FEAT-v1.1.0`）
2. 在特性分支上开发 `feat_list.md` 中对应版本的需求，完成后提交
3. 测试验证通过后，合并回 `master`，打对应版本 tag（如 `v1.1.0`）

**发版时必须同步更新版本号**：`Sources/SayIt/Views/SettingsView.swift` 中搜索 `SayIt v` 字符串，将其更新为对应版本。

## Release Packaging

发版时需分别打包 Intel (x86_64) 和 Apple Silicon (arm64) 两个 DMG。

### 构建

```bash
# 先重新生成 Xcode 工程（如有 project.yml 变更）
xcodegen generate

# Intel (x86_64)
xcodebuild -project SayIt.xcodeproj -scheme SayIt -configuration Release \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  CONFIGURATION_BUILD_DIR="$(pwd)/build/x86_64" \
  clean build

# Apple Silicon (arm64)
xcodebuild -project SayIt.xcodeproj -scheme SayIt -configuration Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CONFIGURATION_BUILD_DIR="$(pwd)/build/arm64" \
  clean build
```

### 打 DMG

```bash
VERSION="v1.2.0"  # 替换为实际版本号

# Intel DMG
hdiutil create -volname "SayIt" \
  -srcfolder "build/x86_64/SayIt.app" \
  -ov -format UDZO \
  "SayIt-${VERSION}-Intel.dmg"

# Apple Silicon DMG
hdiutil create -volname "SayIt" \
  -srcfolder "build/arm64/SayIt.app" \
  -ov -format UDZO \
  "SayIt-${VERSION}-AppleSilicon.dmg"
```

DMG 产物输出到项目根目录：`SayIt-{版本号}-Intel.dmg`、`SayIt-{版本号}-AppleSilicon.dmg`。

## Key Directories

- `Sources/SayIt/Controllers/` — Business logic (audio, STT, LLM, hotkeys, history, context detection)
- `Sources/SayIt/Views/` — SwiftUI views (overlay, settings, history)
- `Sources/SayIt/Controllers/WhisperBridge/` — C++ wrapper for whisper.cpp
- `Tests/SayItTests/` — XCTest unit tests
- `vendor/whisper.cpp/` — Vendored whisper.cpp (do not modify)

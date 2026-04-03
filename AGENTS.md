# AGENTS.md

## Cursor Cloud specific instructions

### Environment overview

This is a native **iOS audiobook player app** (Swift/SwiftUI, `Pageless.xcodeproj`) with zero external dependencies — only Apple frameworks. Full Xcode builds, simulator runs, and device deploys require **macOS with Xcode 26.3+**. The Cloud Agent Linux VM cannot run Xcode or iOS simulators.

### What works on the Linux Cloud Agent VM

| Capability | Tool | Command |
|---|---|---|
| **Lint** (static analysis) | SwiftLint 0.63.2 (static binary) | `swiftlint lint` from repo root |
| **Syntax parse** (all 62 `.swift` files) | Swift 6.1.2 toolchain | `swiftc -parse <file.swift>` |
| **Code review / refactoring** | Any text tool | — |

- Swift toolchain is at `/opt/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin` (added to `PATH` via `~/.bashrc`).
- SwiftLint is a statically-linked binary at `/usr/local/bin/swiftlint` (no SourceKit, so `statement_position` and other SourceKit-dependent rules are skipped).
- `swiftc -parse` validates syntax only; it cannot resolve imports to Apple frameworks (SwiftUI, SwiftData, AVFoundation, etc.), so full type-checking is not possible on Linux.

### What does NOT work on the Linux Cloud Agent VM

- `xcodebuild` — not available (macOS only)
- iOS Simulator — not available (macOS only)
- Full compilation / linking of the app — requires iOS SDK
- Running unit tests (`PagelessTests`) — tests depend on SwiftData and iOS SDK
- UI tests (`PagelessUITests`) — require iOS Simulator or device

### Recommended workflow for code changes

1. Edit Swift source files as needed.
2. Run `swiftlint lint` to check for style/lint violations.
3. Run `swiftc -parse <modified_file.swift>` to verify syntax correctness.
4. For builds and tests, see `CLAUDE.md` — use XcodeBuildMCP tools on macOS or `xcodebuild` with the iPhone 15 device target.

### Project references

- **Build/run/test instructions**: see `CLAUDE.md`
- **Architecture & folder structure**: see `CLAUDE.md` § Architecture
- **AI/FoundationModels reference**: see `APPLE_FOUNDATION_MODELS.md`

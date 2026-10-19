#!/bin/bash
# Compiles a source tree's AI files and Harness.swift into a macOS binary.
# Usage: build.sh <source-root> <out-binary>
# <source-root> holds Pageless/: the repository, or a `git archive` export of another revision.
set -euo pipefail
root="$1"; out="$2"; here="$(cd "$(dirname "$0")" && pwd)"
files=()
# Every Foundation-only or FoundationModels file the two services need, on either side of PR #84.
for f in Models/MomentEnums.swift Utilities/TimeFormatter.swift \
  Services/Protocols/AIPassageContext.swift Services/Protocols/MomentAnalyzing.swift \
  Services/Protocols/RecapProviding.swift Services/AIResponseText.swift \
  Services/MomentAnalysisParser.swift Services/MomentFallbackNamer.swift \
  Services/FoundationModelGeneration.swift Services/MomentNamingService.swift Services/RecapService.swift; do
  [ -f "$root/Pageless/$f" ] && files+=("$root/Pageless/$f")
done
flags=()
[ -f "$root/Pageless/Services/Protocols/AIPassageContext.swift" ] && flags+=(-D PASSAGE_CONTEXT)
[ -f "$root/Pageless/Services/MomentFallbackNamer.swift" ] && flags+=(-D FALLBACK_NAMER)
# The app target's settings: Swift 5 mode, main-actor default isolation, approachable concurrency.
swiftc -O -parse-as-library -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances -target "$(uname -m)-apple-macos27.0" \
  ${flags[@]+"${flags[@]}"} "$here/Harness.swift" "${files[@]}" -o "$out"

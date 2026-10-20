#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --parallel
swift build -Xswiftc -warnings-as-errors
# Compile a separate consumer, without @testable, to catch internal-only initializers.
bin_path="$(swift build --show-bin-path)"
# SwiftPM's native and Swift Build backends place modules in different directories.
swiftc -typecheck -I "$bin_path/Modules" -I "$bin_path" scripts/PublicAPICheck.swift
# A syntax check only; this does NOT type-check against Apple SDKs on Linux.
while IFS= read -r -d '' file; do
  swiftc -frontend -parse "$file"
done < <(find Apps -name '*.swift' -print0)
swift scripts/ValidatePlists.swift

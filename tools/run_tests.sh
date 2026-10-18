#!/bin/sh
# Baut die Diagnose-Logik zusammen mit dem ELM327-Simulator für macOS und führt die Tests aus.
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/lichtlab-tests"
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos13.3" \
  LichtLab/Hex.swift LichtLab/BLEManager.swift LichtLab/ELMSession.swift \
  LichtLab/FaultScanner.swift LichtLab/LightPreset.swift \
  Tests/ELMSimulator.swift Tests/main.swift -o "$OUT"
"$OUT"

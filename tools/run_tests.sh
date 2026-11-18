#!/bin/sh
# Baut die Diagnose-Logik zusammen mit dem ELM327-Simulator für macOS und führt die Tests aus.
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/ridereader-tests"
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macos13.3" \
  RideReader/Hex.swift RideReader/BLEManager.swift RideReader/ELMSession.swift \
  RideReader/FaultScanner.swift RideReader/FaultCatalog.swift RideReader/DPFMonitor.swift \
  Tests/ELMSimulator.swift Tests/main.swift -o "$OUT"
"$OUT"

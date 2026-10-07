#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc -swift-version 6 RedstoneDesktop/World/*.swift RedstoneDesktop/Circuit/*.swift scripts/TerrainPreview.swift -o build/terrain-preview
build/terrain-preview "${1:-build/terrain-preview.svg}"

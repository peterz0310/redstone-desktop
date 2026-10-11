#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
sources=("${(@f)$(rg --files RedstoneDesktop -g '*.swift' -g '!RedstoneDesktopApp.swift')}")
xcrun swiftc -swift-version 6 "${sources[@]}" scripts/PanProfile.swift -o build/pan-profile
build/pan-profile "${1:-RedstoneDesktopTests/Fixtures/SyntheticJava.zip}" "${2:-}"

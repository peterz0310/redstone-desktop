#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build docs/media
sources=("${(@f)$(rg --files RedstoneDesktop -g '*.swift' -g '!RedstoneDesktopApp.swift')}")
xcrun swiftc -swift-version 6 "${sources[@]}" scripts/PolishProfile.swift -o build/polish-profile
build/polish-profile "$PWD/docs/media/circuit-demo.gif"

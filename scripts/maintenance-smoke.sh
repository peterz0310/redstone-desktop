#!/bin/zsh
set -eu
cd "${0:A:h:h}"
sources=("${(@f)$(rg --files RedstoneDesktop -g '*.swift' -g '!RedstoneDesktopApp.swift')}")
xcrun swiftc -DDEBUG -swift-version 6 "${sources[@]}" scripts/MaintenanceSmoke.swift -o build/maintenance-smoke
build/maintenance-smoke "${1:-$PWD/build/Build/Products/Debug/RedstoneDesktop.app}"

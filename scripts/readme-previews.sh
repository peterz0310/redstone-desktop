#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build docs/media
sources=("${(@f)$(rg --files RedstoneDesktop -g '*.swift' -g '!RedstoneDesktopApp.swift')}")
xcrun swiftc -swift-version 6 "${sources[@]}" scripts/ReadmePreviews.swift -o build/readme-previews
build/readme-previews "$PWD/docs/media"
cp RedstoneDesktop/Resources/Assets.xcassets/AppLogo.imageset/logo-light-1x.png docs/media/icon-light.png
cp RedstoneDesktop/Resources/Assets.xcassets/AppLogo.imageset/logo-dark-1x.png docs/media/icon-dark.png

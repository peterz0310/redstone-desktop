#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
# Compile only the generator and original raster art, without the app or Finder.
sources=(LavaPool TreeCanopy WorldGenerator SeededNoise WorldCoordinate ChunkCoordinate Tile TerrainID TerrainDefinition DecorationID DecorationAppearance)
world_sources=()
for name in "${sources[@]}"; do world_sources+=("RedstoneDesktop/World/$name.swift"); done
xcrun swiftc -O -swift-version 6 "${world_sources[@]}" RedstoneDesktop/Rendering/OriginalTerrainPixels.swift scripts/TerrainPreview.swift -o build/terrain-preview
build/terrain-preview "${1:-build/terrain-preview.png}"

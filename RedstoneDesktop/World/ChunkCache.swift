/// Retains only the requested working set. Counters are cumulative; no background generation.
struct ChunkCache {
    private(set) var chunks: [ChunkCoordinate: TerrainChunk] = [:]
    private(set) var generatedCount = 0
    private var settings: WorldGenerationSettings?

    mutating func update(_ requested: Set<ChunkCoordinate>, settings: WorldGenerationSettings) throws {
        if self.settings != settings { chunks.removeAll(); self.settings = settings }
        chunks = chunks.filter { requested.contains($0.key) }
        let generator = try WorldGenerator(settings: settings)
        for coordinate in requested where chunks[coordinate] == nil {
            chunks[coordinate] = try generator.chunk(at: coordinate)
            generatedCount += 1
        }
    }
}

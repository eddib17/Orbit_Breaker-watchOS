import Foundation

public enum LevelError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Loads level definitions bundled as resources at `levels/NNN.json`.
public enum LevelLoader {
    public static func parse(_ data: Data) throws -> LevelDef {
        let level = try JSONDecoder().decode(LevelDef.self, from: data)
        try validate(level)
        return level
    }

    public static func parse(_ text: String) throws -> LevelDef { try parse(Data(text.utf8)) }

    /// `nil` when there is no level with this id.
    public static func load(_ id: Int) throws -> LevelDef? {
        let name = String(format: "%03d", id)
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "levels") else {
            return nil
        }
        return try parse(Data(contentsOf: url))
    }

    /// Loads levels 1, 2, 3… until the first missing file.
    public static func loadAll() throws -> [LevelDef] {
        var levels: [LevelDef] = []
        while let level = try load(levels.count + 1) { levels.append(level) }
        return levels
    }

    public static func validate(_ level: LevelDef) throws {
        func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            if !condition { throw LevelError.invalid(message()) }
        }
        let id = level.id
        try require(!level.rings.isEmpty || level.isBoss, "Level \(id) has no rings or core")
        for (i, ring) in level.rings.enumerated() {
            try require(
                ring.bricks.count == ring.sectors,
                "Level \(id) ring \(i): \(ring.bricks.count) brick codes for \(ring.sectors) sectors"
            )
            for c in ring.bricks { _ = try BrickType.fromCode(c) }
            let inner = ring.radius - Arena.brickThickness / 2
            let outer = ring.radius + Arena.brickThickness / 2
            try require(
                inner >= 0.1 && outer <= Arena.paddleInner - 0.12,
                "Level \(id) ring \(i) radius \(ring.radius) is outside the brick field"
            )
        }
        let sorted = level.rings.map(\.radius).sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            try require(b - a >= Arena.brickThickness, "Level \(id) has overlapping rings at \(a) and \(b)")
        }
        let codes = try level.rings.flatMap { r in try r.bricks.compactMap(BrickType.fromCode) }
        try require(level.isBoss || codes.contains(where: \.breakable), "Level \(id) has no breakable bricks")
        try require(codes.filter { $0 == .warp }.count % 2 == 0, "Level \(id) has an unpaired warp brick")
        let innermost = level.rings.map { $0.radius - Arena.brickThickness / 2 }.min() ?? 1
        for core in level.cores {
            try require(core.hp > 0, "Level \(id) core needs HP")
            try require(
                norm(core.x, core.y) + core.radius + 2 * Arena.ballRadius + 0.01 < innermost,
                "Level \(id) core is too close to the innermost ring for the ball to fit"
            )
        }
        for (i, a) in level.cores.enumerated() {
            for b in level.cores.dropFirst(i + 1) {
                try require(
                    norm(a.x - b.x, a.y - b.y) > a.radius + b.radius + 2 * Arena.ballRadius,
                    "Level \(id) has overlapping cores"
                )
            }
        }
        try require((0...1).contains(level.darkness), "Level \(id) darkness must be 0–1")
        try require(level.paddleShrinkDps >= 0, "Level \(id) paddleShrinkDps must not be negative")
        for well in level.gravityWells {
            try require(well.x * well.x + well.y * well.y < 0.7 * 0.7, "Level \(id): well outside field")
        }
        try require((0...1).contains(level.dropChance), "Level \(id) dropChance must be 0–1")
    }
}

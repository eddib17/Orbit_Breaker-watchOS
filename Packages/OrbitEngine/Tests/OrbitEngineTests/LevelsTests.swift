import Foundation
import Testing
@testable import OrbitEngine

@Suite struct LevelsTests {
    static let levels: [LevelDef] = (try? LevelLoader.loadAll()) ?? []

    @Test func allSixtyLevelsLoadAndValidate() throws {
        let levels = try LevelLoader.loadAll()
        #expect(levels.count == 60)
        #expect(levels.map(\.id) == Array(1...60))
    }

    @Test func worldsMatchLevelNumbers() {
        for level in Self.levels {
            #expect(level.world == Worlds.of(levelId: level.id).number, "level \(level.id)")
        }
        #expect(Worlds.all.count * Worlds.levelsPerWorld == Self.levels.count)
    }

    @Test func everyTenthLevelIsABoss() {
        for level in Self.levels where level.id % Worlds.levelsPerWorld == 0 {
            #expect(level.isBoss, "level \(level.id)")
        }
    }

    @Test func noTwoLevelsAreIdentical() {
        struct Layout: Equatable {
            let rings: [RingDef]
            let cores: [CoreDef]
            let wells: [GravityWellDef]
        }
        let layouts = Self.levels.map { Layout(rings: $0.rings, cores: $0.cores, wells: $0.gravityWells) }
        for i in layouts.indices {
            for j in layouts.indices where j > i {
                #expect(layouts[i] != layouts[j], "levels \(i + 1) and \(j + 1) share a layout")
            }
        }
    }

    @Test func missingFieldsGetKotlinDefaults() throws {
        let level = try LevelLoader.parse("""
        { "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 2, "bricks": "AA" } ] }
        """)
        #expect(level.ballSpeed == 1)
        #expect(level.paddleArcDeg == 40)
        #expect(level.parSeconds == 90)
        #expect(level.regenSeconds == 10)
        #expect(level.phaseSeconds == 1.6)
        #expect(level.darkness == 0)
        #expect(level.dropChance == 0)
        #expect(level.powerUps.isEmpty)
        #expect(level.rings[0].rotationDps == 0)
        #expect(level.rings[0].shield == false)

        let boss = try LevelLoader.parse("""
        { "id": 2, "name": "x", "world": 1,
          "cores": [ { "hp": 3, "phases": [ { "atHp": 1 } ] } ],
          "rings": [ { "radius": 0.4, "sectors": 2, "bricks": "AA" } ] }
        """)
        #expect(boss.cores[0].radius == 0.13)
        #expect(boss.cores[0].phases[0].ringSpeedMultiplier == 1)
        #expect(boss.cores[0].phases[0].gravity == 0)
    }

    @Test(arguments: [
        // Unknown key
        #"{ "id": 1, "name": "x", "world": 1, "speed": 2, "rings": [ { "radius": 0.4, "sectors": 1, "bricks": "A" } ] }"#,
        // Unknown brick code
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 1, "bricks": "Z" } ] }"#,
        // Sector count mismatch
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 3, "bricks": "AA" } ] }"#,
        // Unpaired warp
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 2, "bricks": "AW" } ] }"#,
        // Nothing breakable
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 2, "bricks": "XX" } ] }"#,
        // Ring outside the brick field
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.75, "sectors": 1, "bricks": "A" } ] }"#,
        // Overlapping rings
        #"{ "id": 1, "name": "x", "world": 1, "rings": [ { "radius": 0.4, "sectors": 1, "bricks": "A" }, { "radius": 0.45, "sectors": 1, "bricks": "A" } ] }"#,
        // Core too big for the innermost ring
        #"{ "id": 1, "name": "x", "world": 1, "cores": [ { "hp": 1, "radius": 0.3 } ], "rings": [ { "radius": 0.3, "sectors": 1, "bricks": "A" } ] }"#,
    ])
    func invalidLevelsAreRejected(json: String) {
        #expect(throws: (any Error).self) { try LevelLoader.parse(json) }
    }

    /// The seeded autopilot must clear every level. Each level gets a few attempts (fresh lives) with
    /// different seeds, like a player retrying, and a cap on total game time.
    @Test(arguments: 1...60)
    func autopilotClearsLevel(id: Int) throws {
        let level = try #require(Self.levels.first { $0.id == id })
        let result = botRun(level)
        #expect(result.cleared, "level \(id) \(level.name): \(result.summary)")
    }
}

struct BotResult {
    var cleared = false
    var attempts = 0
    var seconds: Float = 0
    var summary: String { "cleared=\(cleared) after \(attempts) attempt(s), \(Int(seconds)) s" }
}

func botRun(_ level: LevelDef, maxAttempts: Int = 5, maxSecondsPerAttempt: Float = 600) -> BotResult {
    var result = BotResult()
    for attempt in 0..<maxAttempts {
        result.attempts = attempt + 1
        let seed = UInt64(level.id * 1000 + attempt)
        let game = GameEngine(level: level, rng: SplitMix64(seed: seed))
        let bot = Autopilot(rng: SplitMix64(seed: seed &+ 77))
        var t: Float = 0
        while t < maxSecondsPerAttempt {
            bot.steer(game)
            let events = game.update(frameSeconds: 1 / 60)
            bot.onEvents(game, events)
            t += 1 / 60
            if game.state.phase == .cleared {
                result.cleared = true
                result.seconds += t
                return result
            }
            if game.state.phase == .gameOver { break }
        }
        result.seconds += t
    }
    return result
}

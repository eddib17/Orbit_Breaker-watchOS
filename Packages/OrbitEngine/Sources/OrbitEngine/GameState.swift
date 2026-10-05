import Foundation

public enum Phase: Sendable {
    case countdown, playing, cleared, gameOver
}

// The simulation objects are reference types, like the Kotlin classes they port: the engine mutates
// them in place while iterating. The app only reads them.

public final class Ball {
    public internal(set) var x: Float
    public internal(set) var y: Float
    public internal(set) var vx: Float
    public internal(set) var vy: Float
    /// Held by the paddle: before launch, or caught by a sticky paddle.
    public internal(set) var stuck: Bool
    public var radius: Float { Arena.ballRadius }
    /// Angle relative to the paddle center while stuck.
    public internal(set) var stickOffset: Float = 0
    /// Seconds until a sticky-caught ball auto-releases.
    public internal(set) var stickTimer: Float = 0
    /// Warp bricks are ignored until this reaches zero, so the ball can leave the exit portal.
    public internal(set) var warpCooldown: Float = 0
    /// Only a ball fresh off the paddle damages a boss core; the hit spends the charge. Stops a ball
    /// trapped between core and shield from killing the boss on its own.
    public internal(set) var charged = true
    /// A miss warning has fired for the current trip outward.
    public internal(set) var missWarned = false

    public init(x: Float = 0, y: Float = 0, vx: Float = 0, vy: Float = 0, stuck: Bool = true) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.stuck = stuck
    }
}

public final class Paddle {
    /// Center angle of the paddle; unbounded so it can wrap smoothly. Starts at the bottom.
    public internal(set) var angle: Float = 90 * deg
    /// Where input wants the paddle to be; `angle` eases toward it.
    public internal(set) var target: Float
    /// Angular velocity in rad/s, used to put "spin" on the ball.
    public internal(set) var omega: Float = 0
    public let baseHalfArc: Float
    /// Current half-width; animates toward the wide/narrow target when power-ups change it.
    public internal(set) var halfArc: Float

    init(arcDeg: Float) {
        target = angle
        baseHalfArc = arcDeg * deg / 2
        halfArc = baseHalfArc
    }
}

public struct BrickRef: Hashable, Sendable {
    public let ring: Int
    public let index: Int
}

public final class Brick {
    public let type: BrickType
    public internal(set) var hp: Int
    public var alive: Bool { hp > 0 }
    public internal(set) var revealed: Bool
    public internal(set) var regenTimer: Float = 0
    public internal(set) var sonarCooldown: Float = 0
    /// For warp bricks: index of the pair (for coloring) and the linked partner.
    public internal(set) var warpPair = -1
    public internal(set) var warpPartner: BrickRef?
    /// Shield bricks the boss has made phase in and out.
    public internal(set) var phasing: Bool

    init(_ type: BrickType) {
        self.type = type
        hp = type.hitPoints
        revealed = type != .ghost
        phasing = type == .phasing
    }
}

public final class Ring {
    public let def: RingDef
    public let radius: Float
    public let inner: Float
    public let outer: Float
    public let sectors: Int
    public let span: Float
    /// Half of the angular gap between bricks at this ring's radius.
    public let halfGap: Float
    public internal(set) var speedMultiplier: Float = 1
    public internal(set) var rotation: Float
    public let bricks: [Brick?]

    init(_ def: RingDef) {
        self.def = def
        radius = def.radius
        inner = def.radius - Arena.brickThickness / 2
        outer = def.radius + Arena.brickThickness / 2
        sectors = def.sectors
        span = twoPi / Float(def.sectors)
        halfGap = Arena.brickGap / def.radius / 2
        rotation = def.offsetDeg * deg
        bricks = def.bricks.map { BrickType(rawValue: $0).map(Brick.init) }
    }

    /// Current rotation speed (rad/s); tidal rings swing back and forth over `RingDef.rotationPeriod`.
    public func rotationSpeed(at clock: Float) -> Float {
        let tide = def.rotationPeriod > 0 ? sin(clock * twoPi / def.rotationPeriod) : 1
        return def.rotationDps * deg * speedMultiplier * tide
    }

    public func startAngle(_ i: Int) -> Float { rotation + Float(i) * span + halfGap }
    public func endAngle(_ i: Int) -> Float { rotation + Float(i + 1) * span - halfGap }
    public func midAngle(_ i: Int) -> Float { rotation + (Float(i) + 0.5) * span }
}

public final class Core {
    public let def: CoreDef
    public let radius: Float
    public let x: Float
    public let y: Float
    /// Pull toward this core, set by boss phases.
    public internal(set) var gravity: Float = 0
    public internal(set) var hp: Int
    public var alive: Bool { hp > 0 }
    /// Number of boss phases triggered so far.
    public internal(set) var phase = 0
    /// Seconds since last hit, for the flash effect.
    public internal(set) var sinceHit: Float = 10

    init(_ def: CoreDef) {
        self.def = def
        radius = def.radius
        x = def.x
        y = def.y
        hp = def.hp
    }
}

public final class FallingPowerUp {
    public let type: PowerUpType
    public internal(set) var x: Float
    public internal(set) var y: Float

    init(type: PowerUpType, x: Float, y: Float) {
        self.type = type
        self.x = x
        self.y = y
    }
}

public final class LaserBolt {
    public internal(set) var x: Float
    public internal(set) var y: Float
    public let vx: Float
    public let vy: Float
    public internal(set) var traveled: Float = 0

    init(x: Float, y: Float, vx: Float, vy: Float) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }
}

public final class GameState {
    public let level: LevelDef
    public let paddle: Paddle
    public let rings: [Ring]
    public internal(set) var balls: [Ball] = [Ball()]
    public let cores: [Core]
    public var wells: [GravityWellDef] { level.gravityWells }

    public internal(set) var powerUps: [FallingPowerUp] = []
    public internal(set) var bolts: [LaserBolt] = []
    /// Active timed power-ups and their remaining seconds. Iterate in `PowerUpType.allCases` order:
    /// dictionary order is randomized per process and would make runs non-deterministic.
    public internal(set) var effects: [PowerUpType: Float] = [:]
    public internal(set) var shield = false
    public internal(set) var laserCooldown: Float = 0

    public internal(set) var phase = Phase.countdown
    public internal(set) var countdown = Float(Arena.countdownSeconds)
    public internal(set) var lives = Arena.startingLives
    public internal(set) var livesLost = 0
    public internal(set) var score = 0
    public internal(set) var combo = 0
    /// Time spent playing (excludes countdowns); used for the par-time star.
    public internal(set) var elapsed: Float = 0
    /// Total simulated time; drives animations like phasing.
    public internal(set) var clock: Float = 0
    public internal(set) var stars = 0

    public let baseSpeed: Float
    /// Ball speed before slow-mo; ramps up with paddle hits.
    public internal(set) var speed: Float
    public var ballSpeed: Float { speed * (isActive(.slow) ? Arena.slowFactor : 1) }

    public internal(set) var sinceBrickHit: Float = 0
    public internal(set) var stallNudgePending = false

    init(level: LevelDef) {
        self.level = level
        paddle = Paddle(arcDeg: level.paddleArcDeg)
        rings = level.rings.map(Ring.init)
        cores = level.cores.map(Core.init)
        baseSpeed = Arena.baseBallSpeed * level.ballSpeed
        speed = baseSpeed
    }

    public var breakableRemaining: Int {
        rings.reduce(0) { sum, r in sum + r.bricks.count { $0 != nil && $0!.alive && $0!.type.breakable } }
    }

    public func isActive(_ type: PowerUpType) -> Bool { effects[type] != nil }

    /// Phasing bricks alternate by index so half of a ring is always solid.
    public func isTangible(ring: Int, index: Int) -> Bool {
        guard let brick = rings[ring].bricks[index], brick.alive else { return false }
        if !brick.phasing { return true }
        return (Int(clock / level.phaseSeconds) + index) % 2 == 0
    }
}

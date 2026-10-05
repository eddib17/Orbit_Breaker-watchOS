// Synthesized `Decodable` ignores default property values, so every type here decodes by hand with
// `decodeIfPresent(...) ?? default`. Unknown keys are rejected, like the Kotlin `ignoreUnknownKeys = false`.

public struct LevelDef: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var world: Int
    public var ballSpeed: Float = 1
    public var paddleArcDeg: Float = Arena.defaultPaddleArcDeg
    public var parSeconds: Int = 90
    public var rings: [RingDef]
    public var gravityWells: [GravityWellDef] = []
    /// Boss cores. When present, destroying all of them clears the level (other bricks don't matter).
    public var cores: [CoreDef] = []
    /// Power-ups that carrier bricks can drop. Empty means every type.
    public var powerUps: [PowerUpType] = []
    /// Chance (0–1) that a non-carrier brick also drops a power-up.
    public var dropChance: Float = 0
    public var regenSeconds: Float = 10
    /// How long phasing bricks stay solid (and then intangible).
    public var phaseSeconds: Float = 1.6
    /// 0 = normal, 1 = pitch black. Bricks are only visible near the ball; dark levels (≥ 0.5) add haptic sonar for every brick.
    public var darkness: Float = 0
    /// The paddle arc shrinks by this many degrees per second of play, down to `Arena.minPaddleArcDeg`.
    public var paddleShrinkDps: Float = 0

    public var isBoss: Bool { !cores.isEmpty }

    public init(
        id: Int, name: String, world: Int, ballSpeed: Float = 1,
        paddleArcDeg: Float = Arena.defaultPaddleArcDeg, parSeconds: Int = 90, rings: [RingDef],
        gravityWells: [GravityWellDef] = [], cores: [CoreDef] = [], powerUps: [PowerUpType] = [],
        dropChance: Float = 0, regenSeconds: Float = 10, phaseSeconds: Float = 1.6,
        darkness: Float = 0, paddleShrinkDps: Float = 0
    ) {
        self.id = id
        self.name = name
        self.world = world
        self.ballSpeed = ballSpeed
        self.paddleArcDeg = paddleArcDeg
        self.parSeconds = parSeconds
        self.rings = rings
        self.gravityWells = gravityWells
        self.cores = cores
        self.powerUps = powerUps
        self.dropChance = dropChance
        self.regenSeconds = regenSeconds
        self.phaseSeconds = phaseSeconds
        self.darkness = darkness
        self.paddleShrinkDps = paddleShrinkDps
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, world, ballSpeed, paddleArcDeg, parSeconds, rings, gravityWells, cores, powerUps
        case dropChance, regenSeconds, phaseSeconds, darkness, paddleShrinkDps
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        world = try c.decode(Int.self, forKey: .world)
        ballSpeed = try c.decodeIfPresent(Float.self, forKey: .ballSpeed) ?? 1
        paddleArcDeg = try c.decodeIfPresent(Float.self, forKey: .paddleArcDeg) ?? Arena.defaultPaddleArcDeg
        parSeconds = try c.decodeIfPresent(Int.self, forKey: .parSeconds) ?? 90
        rings = try c.decode([RingDef].self, forKey: .rings)
        gravityWells = try c.decodeIfPresent([GravityWellDef].self, forKey: .gravityWells) ?? []
        cores = try c.decodeIfPresent([CoreDef].self, forKey: .cores) ?? []
        powerUps = try c.decodeIfPresent([PowerUpType].self, forKey: .powerUps) ?? []
        dropChance = try c.decodeIfPresent(Float.self, forKey: .dropChance) ?? 0
        regenSeconds = try c.decodeIfPresent(Float.self, forKey: .regenSeconds) ?? 10
        phaseSeconds = try c.decodeIfPresent(Float.self, forKey: .phaseSeconds) ?? 1.6
        darkness = try c.decodeIfPresent(Float.self, forKey: .darkness) ?? 0
        paddleShrinkDps = try c.decodeIfPresent(Float.self, forKey: .paddleShrinkDps) ?? 0
    }
}

public struct RingDef: Decodable, Equatable, Sendable {
    public var radius: Float
    public var sectors: Int
    public var bricks: String
    /// Ring rotation speed in degrees per second; positive is clockwise.
    public var rotationDps: Float = 0
    /// Initial rotation of the ring in degrees.
    public var offsetDeg: Float = 0
    /// If > 0, rotation speed swings like a tide: rotationDps × sin(2π·t / period), reversing direction.
    public var rotationPeriod: Float = 0
    /// Shield rings are restored when a boss phase has `restoreShields`.
    public var shield: Bool = false

    public init(
        radius: Float, sectors: Int, bricks: String, rotationDps: Float = 0, offsetDeg: Float = 0,
        rotationPeriod: Float = 0, shield: Bool = false
    ) {
        self.radius = radius
        self.sectors = sectors
        self.bricks = bricks
        self.rotationDps = rotationDps
        self.offsetDeg = offsetDeg
        self.rotationPeriod = rotationPeriod
        self.shield = shield
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case radius, sectors, bricks, rotationDps, offsetDeg, rotationPeriod, shield
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radius = try c.decode(Float.self, forKey: .radius)
        sectors = try c.decode(Int.self, forKey: .sectors)
        bricks = try c.decode(String.self, forKey: .bricks)
        rotationDps = try c.decodeIfPresent(Float.self, forKey: .rotationDps) ?? 0
        offsetDeg = try c.decodeIfPresent(Float.self, forKey: .offsetDeg) ?? 0
        rotationPeriod = try c.decodeIfPresent(Float.self, forKey: .rotationPeriod) ?? 0
        shield = try c.decodeIfPresent(Bool.self, forKey: .shield) ?? false
    }
}

public struct GravityWellDef: Decodable, Equatable, Sendable {
    public var x: Float = 0
    public var y: Float = 0
    /// Pull strength; ~0.05 is gentle, ~0.2 is strong.
    public var strength: Float
    /// If > 0, the pull pulses between 0 and full strength with this period.
    public var pulseSeconds: Float = 0

    public init(x: Float = 0, y: Float = 0, strength: Float, pulseSeconds: Float = 0) {
        self.x = x
        self.y = y
        self.strength = strength
        self.pulseSeconds = pulseSeconds
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, strength, pulseSeconds
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Float.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Float.self, forKey: .y) ?? 0
        strength = try c.decode(Float.self, forKey: .strength)
        pulseSeconds = try c.decodeIfPresent(Float.self, forKey: .pulseSeconds) ?? 0
    }
}

public struct CoreDef: Decodable, Equatable, Sendable {
    public var hp: Int
    public var radius: Float = 0.13
    /// Position; off-center cores must still sit inside the innermost ring.
    public var x: Float = 0
    public var y: Float = 0
    public var phases: [CorePhaseDef] = []

    public init(hp: Int, radius: Float = 0.13, x: Float = 0, y: Float = 0, phases: [CorePhaseDef] = []) {
        self.hp = hp
        self.radius = radius
        self.x = x
        self.y = y
        self.phases = phases
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case hp, radius, x, y, phases
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hp = try c.decode(Int.self, forKey: .hp)
        radius = try c.decodeIfPresent(Float.self, forKey: .radius) ?? 0.13
        x = try c.decodeIfPresent(Float.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Float.self, forKey: .y) ?? 0
        phases = try c.decodeIfPresent([CorePhaseDef].self, forKey: .phases) ?? []
    }
}

/// Triggered once when the core's HP drops to `atHp` or below.
public struct CorePhaseDef: Decodable, Equatable, Sendable {
    public var atHp: Int
    public var ringSpeedMultiplier: Float = 1
    /// Turns this core into a gravity well of this strength.
    public var gravity: Float = 0
    public var restoreShields: Bool = false
    /// Makes every shield-ring brick phase in and out.
    public var phaseShields: Bool = false

    public init(
        atHp: Int, ringSpeedMultiplier: Float = 1, gravity: Float = 0, restoreShields: Bool = false,
        phaseShields: Bool = false
    ) {
        self.atHp = atHp
        self.ringSpeedMultiplier = ringSpeedMultiplier
        self.gravity = gravity
        self.restoreShields = restoreShields
        self.phaseShields = phaseShields
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case atHp, ringSpeedMultiplier, gravity, restoreShields, phaseShields
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        atHp = try c.decode(Int.self, forKey: .atHp)
        ringSpeedMultiplier = try c.decodeIfPresent(Float.self, forKey: .ringSpeedMultiplier) ?? 1
        gravity = try c.decodeIfPresent(Float.self, forKey: .gravity) ?? 0
        restoreShields = try c.decodeIfPresent(Bool.self, forKey: .restoreShields) ?? false
        phaseShields = try c.decodeIfPresent(Bool.self, forKey: .phaseShields) ?? false
    }
}

public enum BrickType: Character, CaseIterable, Sendable {
    case standard = "A"
    case tough = "B"
    case armored = "C"
    case unbreakable = "X"
    /// Destroys its neighbours when it breaks; neighbours that are explosive chain.
    case explosive = "E"
    /// Always drops a power-up.
    case carrier = "P"
    /// Grows back after the level's regenSeconds, unless the rest of its ring has been cleared.
    case regen = "R"
    /// Invisible until the first hit reveals it; the second hit breaks it.
    case ghost = "G"
    /// Alternates between solid and intangible every phaseSeconds.
    case phasing = "F"
    /// Unbreakable portal; consecutive W bricks in a level are linked in pairs.
    case warp = "W"

    public var code: Character { rawValue }

    public var hitPoints: Int {
        switch self {
        case .tough, .ghost: 2
        case .armored: 3
        case .unbreakable, .warp: .max
        default: 1
        }
    }

    public var breakable: Bool { self != .unbreakable && self != .warp }

    /// `nil` for an empty slot (`.`); throws on an unknown code.
    public static func fromCode(_ c: Character) throws -> BrickType? {
        if c == "." { return nil }
        guard let type = BrickType(rawValue: c) else { throw LevelError.invalid("Unknown brick code '\(c)'") }
        return type
    }
}

public enum PowerUpType: String, CaseIterable, Decodable, Sendable {
    case wide = "WIDE"
    case shrink = "SHRINK"
    case multi = "MULTI"
    case slow = "SLOW"
    case fire = "FIRE"
    case sticky = "STICKY"
    case laser = "LASER"
    case shield = "SHIELD"
    case life = "LIFE"

    public var glyph: String {
        switch self {
        case .wide: "W"
        case .shrink: "N"
        case .multi: "M"
        case .slow: "S"
        case .fire: "F"
        case .sticky: "G"
        case .laser: "L"
        case .shield: "O"
        case .life: "+"
        }
    }

    public var label: String {
        switch self {
        case .wide: "Wide paddle"
        case .shrink: "Narrow paddle"
        case .multi: "Multi-ball"
        case .slow: "Slow-mo"
        case .fire: "Fireball"
        case .sticky: "Sticky paddle"
        case .laser: "Laser"
        case .shield: "Shield ring"
        case .life: "Extra life"
        }
    }

    public var positive: Bool { self != .shrink }

    /// Effect length in seconds; 0 for instant effects.
    public var duration: Float {
        switch self {
        case .wide: 15
        case .shrink: 12
        case .slow: 10
        case .fire: 8
        case .sticky: 12
        case .laser: 8
        case .multi, .shield, .life: 0
        }
    }

    /// Relative drop weight.
    public var weight: Float {
        switch self {
        case .wide, .multi: 2
        case .shrink, .fire, .laser, .shield: 1
        case .slow, .sticky: 1.5
        case .life: 0.4
        }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func rejectUnknownKeys<K: CodingKey & CaseIterable>(_ decoder: Decoder, _: K.Type) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    let known = Set(K.allCases.map(\.stringValue))
    if let unknown = container.allKeys.first(where: { !known.contains($0.stringValue) }) {
        throw DecodingError.dataCorruptedError(
            forKey: unknown, in: container, debugDescription: "Unknown key '\(unknown.stringValue)'"
        )
    }
}

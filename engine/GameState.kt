package com.orbitbreaker.engine

import kotlin.math.sin

enum class Phase { COUNTDOWN, PLAYING, CLEARED, GAME_OVER }

class Ball(
    var x: Float = 0f,
    var y: Float = 0f,
    var vx: Float = 0f,
    var vy: Float = 0f,
    /** Held by the paddle: before launch, or caught by a sticky paddle. */
    var stuck: Boolean = true,
) {
    val radius: Float get() = Arena.BALL_RADIUS
    /** Angle relative to the paddle center while stuck. */
    var stickOffset = 0f
    /** Seconds until a sticky-caught ball auto-releases. */
    var stickTimer = 0f
    /** Warp bricks are ignored until this reaches zero, so the ball can leave the exit portal. */
    var warpCooldown = 0f
    /**
     * Only a ball fresh off the paddle damages a boss core; the hit spends the charge. Stops a ball
     * trapped between core and shield from killing the boss on its own.
     */
    var charged = true
    /** A miss warning has fired for the current trip outward. */
    var missWarned = false
}

class Paddle(arcDeg: Float) {
    /** Center angle of the paddle; unbounded so it can wrap smoothly. Starts at the bottom. */
    var angle: Float = 90f * DEG
    /** Where input wants the paddle to be; [angle] eases toward it. */
    var target: Float = angle
    /** Angular velocity in rad/s, used to put "spin" on the ball. */
    var omega: Float = 0f
    val baseHalfArc: Float = arcDeg * DEG / 2f
    /** Current half-width; animates toward the wide/narrow target when power-ups change it. */
    var halfArc: Float = baseHalfArc
}

class Brick(val type: BrickType) {
    var hp: Int = type.hitPoints
    val alive: Boolean get() = hp > 0
    var revealed: Boolean = type != BrickType.GHOST
    var regenTimer = 0f
    var sonarCooldown = 0f
    /** For warp bricks: index of the pair (for coloring) and the linked partner. */
    var warpPair = -1
    var warpPartner: Pair<Int, Int>? = null
    /** Shield bricks the boss has made phase in and out. */
    var phasing = type == BrickType.PHASING
}

class Ring(val def: RingDef) {
    val radius = def.radius
    val inner = def.radius - Arena.BRICK_THICKNESS / 2f
    val outer = def.radius + Arena.BRICK_THICKNESS / 2f
    val sectors = def.sectors
    val span = TWO_PI / def.sectors
    /** Half of the angular gap between bricks at this ring's radius. */
    val halfGap = Arena.BRICK_GAP / def.radius / 2f
    var speedMultiplier = 1f
    var rotation = def.offsetDeg * DEG
    val bricks: List<Brick?> = def.bricks.map { c -> BrickType.fromCode(c)?.let(::Brick) }

    /** Current rotation speed (rad/s); tidal rings swing back and forth over [RingDef.rotationPeriod]. */
    fun rotationSpeedAt(clock: Float): Float {
        val tide = if (def.rotationPeriod > 0f) sin(clock * TWO_PI / def.rotationPeriod) else 1f
        return def.rotationDps * DEG * speedMultiplier * tide
    }
    fun startAngle(i: Int) = rotation + i * span + halfGap
    fun endAngle(i: Int) = rotation + (i + 1) * span - halfGap
    fun midAngle(i: Int) = rotation + (i + 0.5f) * span
}

class Core(val def: CoreDef) {
    val radius = def.radius
    val x = def.x
    val y = def.y
    /** Pull toward this core, set by boss phases. */
    var gravity = 0f
    var hp = def.hp
    val alive get() = hp > 0
    /** Number of boss phases triggered so far. */
    var phase = 0
    /** Seconds since last hit, for the flash effect. */
    var sinceHit = 10f
}

class FallingPowerUp(val type: PowerUpType, var x: Float, var y: Float)

class LaserBolt(var x: Float, var y: Float, val vx: Float, val vy: Float, var traveled: Float = 0f)

class GameState(val level: LevelDef) {
    val paddle = Paddle(level.paddleArcDeg)
    val rings: List<Ring> = level.rings.map(::Ring)
    val balls = mutableListOf(Ball())
    val cores: List<Core> = level.cores.map(::Core)
    val wells: List<GravityWellDef> = level.gravityWells

    val powerUps = mutableListOf<FallingPowerUp>()
    val bolts = mutableListOf<LaserBolt>()
    /** Active timed power-ups and their remaining seconds. */
    val effects = mutableMapOf<PowerUpType, Float>()
    var shield = false
    var laserCooldown = 0f

    var phase = Phase.COUNTDOWN
    var countdown = Arena.COUNTDOWN_SECONDS.toFloat()
    var lives = Arena.STARTING_LIVES
    var livesLost = 0
    var score = 0
    var combo = 0
    /** Time spent playing (excludes countdowns); used for the par-time star. */
    var elapsed = 0f
    /** Total simulated time; drives animations like phasing. */
    var clock = 0f
    var stars = 0

    val baseSpeed = Arena.BASE_BALL_SPEED * level.ballSpeed
    /** Ball speed before slow-mo; ramps up with paddle hits. */
    var speed = baseSpeed
    val ballSpeed: Float get() = speed * if (PowerUpType.SLOW in effects) Arena.SLOW_FACTOR else 1f

    var sinceBrickHit = 0f
    var stallNudgePending = false

    val breakableRemaining: Int
        get() = rings.sumOf { r -> r.bricks.count { it != null && it.alive && it.type.breakable } }

    fun isActive(type: PowerUpType) = type in effects

    /** Phasing bricks alternate by index so half of a ring is always solid. */
    fun isTangible(ring: Int, index: Int): Boolean {
        val brick = rings[ring].bricks[index] ?: return false
        if (!brick.alive) return false
        if (!brick.phasing) return true
        return ((clock / level.phaseSeconds).toInt() + index) % 2 == 0
    }
}

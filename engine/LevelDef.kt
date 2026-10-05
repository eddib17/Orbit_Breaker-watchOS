package com.orbitbreaker.engine

import kotlinx.serialization.Serializable

@Serializable
data class LevelDef(
    val id: Int,
    val name: String,
    val world: Int,
    val ballSpeed: Float = 1f,
    val paddleArcDeg: Float = Arena.DEFAULT_PADDLE_ARC_DEG,
    val parSeconds: Int = 90,
    val rings: List<RingDef>,
    val gravityWells: List<GravityWellDef> = emptyList(),
    /** Boss cores. When present, destroying all of them clears the level (other bricks don't matter). */
    val cores: List<CoreDef> = emptyList(),
    /** Power-ups that carrier bricks can drop. Empty means every type. */
    val powerUps: List<PowerUpType> = emptyList(),
    /** Chance (0–1) that a non-carrier brick also drops a power-up. */
    val dropChance: Float = 0f,
    val regenSeconds: Float = 10f,
    /** How long phasing bricks stay solid (and then intangible). */
    val phaseSeconds: Float = 1.6f,
    /** 0 = normal, 1 = pitch black. Bricks are only visible near the ball; dark levels (≥ 0.5) add haptic sonar for every brick. */
    val darkness: Float = 0f,
    /** The paddle arc shrinks by this many degrees per second of play, down to [Arena.MIN_PADDLE_ARC_DEG]. */
    val paddleShrinkDps: Float = 0f,
) {
    val isBoss: Boolean get() = cores.isNotEmpty()
}

@Serializable
data class RingDef(
    val radius: Float,
    val sectors: Int,
    val bricks: String,
    /** Ring rotation speed in degrees per second; positive is clockwise. */
    val rotationDps: Float = 0f,
    /** Initial rotation of the ring in degrees. */
    val offsetDeg: Float = 0f,
    /** If > 0, rotation speed swings like a tide: rotationDps × sin(2π·t / period), reversing direction. */
    val rotationPeriod: Float = 0f,
    /** Shield rings are restored when a boss phase has `restoreShields`. */
    val shield: Boolean = false,
)

@Serializable
data class GravityWellDef(
    val x: Float = 0f,
    val y: Float = 0f,
    /** Pull strength; ~0.05 is gentle, ~0.2 is strong. */
    val strength: Float,
    /** If > 0, the pull pulses between 0 and full strength with this period. */
    val pulseSeconds: Float = 0f,
)

@Serializable
data class CoreDef(
    val hp: Int,
    val radius: Float = 0.13f,
    /** Position; off-center cores must still sit inside the innermost ring. */
    val x: Float = 0f,
    val y: Float = 0f,
    val phases: List<CorePhaseDef> = emptyList(),
)

/** Triggered once when the core's HP drops to [atHp] or below. */
@Serializable
data class CorePhaseDef(
    val atHp: Int,
    val ringSpeedMultiplier: Float = 1f,
    /** Turns this core into a gravity well of this strength. */
    val gravity: Float = 0f,
    val restoreShields: Boolean = false,
    /** Makes every shield-ring brick phase in and out. */
    val phaseShields: Boolean = false,
)

enum class BrickType(val code: Char, val hitPoints: Int, val breakable: Boolean = true) {
    STANDARD('A', 1),
    TOUGH('B', 2),
    ARMORED('C', 3),
    UNBREAKABLE('X', Int.MAX_VALUE, breakable = false),
    /** Destroys its neighbours when it breaks; neighbours that are explosive chain. */
    EXPLOSIVE('E', 1),
    /** Always drops a power-up. */
    CARRIER('P', 1),
    /** Grows back after the level's regenSeconds, unless the rest of its ring has been cleared. */
    REGEN('R', 1),
    /** Invisible until the first hit reveals it; the second hit breaks it. */
    GHOST('G', 2),
    /** Alternates between solid and intangible every phaseSeconds. */
    PHASING('F', 1),
    /** Unbreakable portal; consecutive W bricks in a level are linked in pairs. */
    WARP('W', Int.MAX_VALUE, breakable = false);

    companion object {
        fun fromCode(c: Char): BrickType? =
            if (c == '.') null
            else entries.firstOrNull { it.code == c } ?: throw IllegalArgumentException("Unknown brick code '$c'")
    }
}

enum class PowerUpType(
    val glyph: String,
    val label: String,
    val positive: Boolean,
    /** Effect length in seconds; 0 for instant effects. */
    val duration: Float,
    /** Relative drop weight. */
    val weight: Float,
) {
    WIDE("W", "Wide paddle", true, 15f, 2f),
    SHRINK("N", "Narrow paddle", false, 12f, 1f),
    MULTI("M", "Multi-ball", true, 0f, 2f),
    SLOW("S", "Slow-mo", true, 10f, 1.5f),
    FIRE("F", "Fireball", true, 8f, 1f),
    STICKY("G", "Sticky paddle", true, 12f, 1.5f),
    LASER("L", "Laser", true, 8f, 1f),
    SHIELD("O", "Shield ring", true, 0f, 1f),
    LIFE("+", "Extra life", true, 0f, 0.4f),
}

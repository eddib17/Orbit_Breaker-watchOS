package com.orbitbreaker.engine

/** Things that happened during a simulation step. Consumed by haptics, particles and sound. */
sealed interface GameEvent {
    data class CountdownTick(val remaining: Int) : GameEvent
    /** A ball left the paddle: the initial launch or a sticky-paddle release. */
    data object Launched : GameEvent
    /** [offset] is -1 at one edge of the paddle, 0 at its center and +1 at the other edge. */
    data class PaddleHit(val offset: Float) : GameEvent
    data class BrickDamaged(val ring: Int, val index: Int, val hpLeft: Int) : GameEvent
    data class BrickDestroyed(val ring: Int, val index: Int, val type: BrickType, val x: Float, val y: Float) : GameEvent
    data object UnbreakableHit : GameEvent
    data class ComboMilestone(val tier: Int, val combo: Int) : GameEvent
    data object StallNudge : GameEvent
    /**
     * The ball will reach the paddle ring within [Arena.MISS_WARNING_SECONDS] and the paddle isn't
     * heading there. An accessibility aid; the app only plays it when the player opts in.
     */
    data object MissWarning : GameEvent

    data class Explosion(val x: Float, val y: Float) : GameEvent
    data class BrickRegenerated(val ring: Int, val index: Int) : GameEvent
    data class GhostRevealed(val ring: Int, val index: Int) : GameEvent
    /** The ball passed close to a still-hidden ghost brick. */
    data object GhostNear : GameEvent
    data class Warped(val x: Float, val y: Float) : GameEvent

    data class PowerUpSpawned(val type: PowerUpType) : GameEvent
    data class PowerUpCollected(val type: PowerUpType, val x: Float, val y: Float) : GameEvent
    /** A timed power-up has two seconds left. */
    data class PowerUpEnding(val type: PowerUpType) : GameEvent
    data class PowerUpExpired(val type: PowerUpType) : GameEvent
    data object BallCaught : GameEvent
    data object LaserFired : GameEvent
    data object ShieldSaved : GameEvent
    /** One of several balls fell out; no life lost. */
    data object BallDropped : GameEvent

    data class BossHit(val hpLeft: Int) : GameEvent
    /** An uncharged ball bounced off a core without damaging it. */
    data object CoreDeflected : GameEvent
    data class BossPhase(val phase: Int) : GameEvent
    data object BossDefeated : GameEvent

    data class BallLost(val livesLeft: Int) : GameEvent
    data class LevelCleared(val stars: Int, val score: Int) : GameEvent
    data object GameOver : GameEvent
}

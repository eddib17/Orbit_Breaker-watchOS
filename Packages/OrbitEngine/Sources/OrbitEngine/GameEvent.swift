/// Things that happened during a simulation step. Consumed by haptics, particles and sound.
public enum GameEvent: Equatable, Sendable {
    case countdownTick(remaining: Int)
    /// A ball left the paddle: the initial launch or a sticky-paddle release.
    case launched
    /// `offset` is -1 at one edge of the paddle, 0 at its center and +1 at the other edge.
    case paddleHit(offset: Float)
    case brickDamaged(ring: Int, index: Int, hpLeft: Int)
    case brickDestroyed(ring: Int, index: Int, type: BrickType, x: Float, y: Float)
    case unbreakableHit
    case comboMilestone(tier: Int, combo: Int)
    case stallNudge
    /// The ball will reach the paddle ring within `Arena.missWarningSeconds` and the paddle isn't
    /// heading there. An accessibility aid; the app only plays it when the player opts in.
    case missWarning

    case explosion(x: Float, y: Float)
    case brickRegenerated(ring: Int, index: Int)
    case ghostRevealed(ring: Int, index: Int)
    /// The ball passed close to a still-hidden ghost brick.
    case ghostNear
    case warped(x: Float, y: Float)

    case powerUpSpawned(PowerUpType)
    case powerUpCollected(PowerUpType, x: Float, y: Float)
    /// A timed power-up has two seconds left.
    case powerUpEnding(PowerUpType)
    case powerUpExpired(PowerUpType)
    case ballCaught
    case laserFired
    case shieldSaved
    /// One of several balls fell out; no life lost.
    case ballDropped

    case bossHit(hpLeft: Int)
    /// An uncharged ball bounced off a core without damaging it.
    case coreDeflected
    case bossPhase(Int)
    case bossDefeated

    case ballLost(livesLeft: Int)
    case levelCleared(stars: Int, score: Int)
    case gameOver
}

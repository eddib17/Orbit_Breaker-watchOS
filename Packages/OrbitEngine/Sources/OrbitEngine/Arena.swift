/// Arena geometry in normalized units: the playfield is a circle of radius 1.0 centered on (0, 0).
/// Angles are in radians, measured from +x and increasing clockwise on screen (y points down).
public enum Arena {
    public static let paddleRadius: Float = 0.88
    public static let paddleThickness: Float = 0.05
    public static let paddleInner: Float = paddleRadius - paddleThickness / 2
    public static let paddleOuter: Float = paddleRadius + paddleThickness / 2
    public static let defaultPaddleArcDeg: Float = 40
    public static let minPaddleArcDeg: Float = 20

    public static let ballRadius: Float = 0.035
    public static let killRadius: Float = 0.98

    public static let brickThickness: Float = 0.085
    /// Gap between neighbouring bricks, in arena units along the arc.
    public static let brickGap: Float = 0.014

    /// Base ball speed in arena radii per second, multiplied by the level's ballSpeed.
    public static let baseBallSpeed: Float = 0.85
    public static let speedRampPerHit: Float = 0.015
    public static let maxSpeedFactor: Float = 1.6

    /// Maximum deflection from straight-inward when the ball hits the very edge of the paddle.
    public static let maxDeflectDeg: Float = 55
    public static let absoluteMaxDeflectDeg: Float = 65

    public static let startingLives = 3
    public static let maxLives = 5
    public static let maxBalls = 6
    public static let countdownSeconds = 3
    public static let stallSeconds: Float = 8
    public static let stallNudgeDeg: Float = 7

    // Mechanics
    public static let sonarRange: Float = 0.08
    public static let sonarCooldown: Float = 0.6
    /// Levels at least this dark give sonar ticks for every brick, not just ghosts.
    public static let darkSonarThreshold: Float = 0.5
    public static let warpCooldown: Float = 0.4
    public static let explosionReach: Float = 0.05

    // Power-ups
    public static let powerUpRadius: Float = 0.035
    public static let powerUpSpeed: Float = 0.32
    public static let wideFactor: Float = 1.5
    public static let shrinkFactor: Float = 0.7
    public static let slowFactor: Float = 0.65
    public static let multiSpreadDeg: Float = 25
    public static let stickyHoldSeconds: Float = 2
    public static let laserInterval: Float = 0.45
    public static let laserSpeed: Float = 1.6
    public static let shieldRadius: Float = 0.94
    public static let powerUpWarningSeconds: Float = 2

    /// How far ahead the miss warning looks: time until the ball reaches the paddle ring.
    public static let missWarningSeconds: Float = 0.45

    public static let coreHitScore = 25
    public static let coreDefeatScore = 500

    /// Fixed physics substep. Movement per substep is also capped relative to the ball radius.
    public static let fixedStep: Float = 1 / 120
}

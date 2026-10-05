package com.orbitbreaker.engine

/**
 * Arena geometry in normalized units: the playfield is a circle of radius 1.0 centered on (0, 0).
 * Angles are in radians, measured from +x and increasing clockwise on screen (y points down).
 */
object Arena {
    const val PADDLE_RADIUS = 0.88f
    const val PADDLE_THICKNESS = 0.05f
    const val PADDLE_INNER = PADDLE_RADIUS - PADDLE_THICKNESS / 2f
    const val PADDLE_OUTER = PADDLE_RADIUS + PADDLE_THICKNESS / 2f
    const val DEFAULT_PADDLE_ARC_DEG = 40f
    const val MIN_PADDLE_ARC_DEG = 20f

    const val BALL_RADIUS = 0.035f
    const val KILL_RADIUS = 0.98f

    const val BRICK_THICKNESS = 0.085f
    /** Gap between neighbouring bricks, in arena units along the arc. */
    const val BRICK_GAP = 0.014f

    /** Base ball speed in arena radii per second, multiplied by the level's ballSpeed. */
    const val BASE_BALL_SPEED = 0.85f
    const val SPEED_RAMP_PER_HIT = 0.015f
    const val MAX_SPEED_FACTOR = 1.6f

    /** Maximum deflection from straight-inward when the ball hits the very edge of the paddle. */
    const val MAX_DEFLECT_DEG = 55f
    const val ABSOLUTE_MAX_DEFLECT_DEG = 65f

    const val STARTING_LIVES = 3
    const val MAX_LIVES = 5
    const val MAX_BALLS = 6
    const val COUNTDOWN_SECONDS = 3
    const val STALL_SECONDS = 8f
    const val STALL_NUDGE_DEG = 7f

    // Mechanics
    const val SONAR_RANGE = 0.08f
    const val SONAR_COOLDOWN = 0.6f
    /** Levels at least this dark give sonar ticks for every brick, not just ghosts. */
    const val DARK_SONAR_THRESHOLD = 0.5f
    const val WARP_COOLDOWN = 0.4f
    const val EXPLOSION_REACH = 0.05f

    // Power-ups
    const val POWERUP_RADIUS = 0.035f
    const val POWERUP_SPEED = 0.32f
    const val WIDE_FACTOR = 1.5f
    const val SHRINK_FACTOR = 0.7f
    const val SLOW_FACTOR = 0.65f
    const val MULTI_SPREAD_DEG = 25f
    const val STICKY_HOLD_SECONDS = 2f
    const val LASER_INTERVAL = 0.45f
    const val LASER_SPEED = 1.6f
    const val SHIELD_RADIUS = 0.94f
    const val POWERUP_WARNING_SECONDS = 2f

    /** How far ahead the miss warning looks: time until the ball reaches the paddle ring. */
    const val MISS_WARNING_SECONDS = 0.45f

    const val CORE_HIT_SCORE = 25
    const val CORE_DEFEAT_SCORE = 500

    /** Fixed physics substep. Movement per substep is also capped relative to the ball radius. */
    const val FIXED_STEP = 1f / 120f
}

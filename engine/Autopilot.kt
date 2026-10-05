package com.orbitbreaker.engine

import kotlin.random.Random

/**
 * A simple player: steers the paddle to where the ball will cross the paddle ring, with a random
 * aim offset after each hit so it doesn't bounce straight through the center forever.
 * Used by tests to prove levels are winnable and by the How to Play demo.
 */
class Autopilot(private val random: Random = Random.Default) {
    private var aimOffset = 0f

    /** Call before each [GameEngine.update]. */
    fun steer(engine: GameEngine) {
        val ball = engine.state.balls.firstOrNull { !it.stuck && it.x * it.vx + it.y * it.vy > 0f }
            ?: engine.state.balls.firstOrNull { !it.stuck }
            ?: return
        engine.aimPaddle(predictedExitAngle(ball) + aimOffset)
    }

    /** Call with the events from each [GameEngine.update]. */
    fun onEvents(engine: GameEngine, events: List<GameEvent>) {
        if (events.any { it is GameEvent.PaddleHit }) {
            aimOffset = (random.nextFloat() - 0.5f) * engine.state.paddle.halfArc
        }
    }
}

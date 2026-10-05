package com.orbitbreaker.engine

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.sqrt

internal const val TWO_PI = (2 * PI).toFloat()
internal const val DEG = (PI / 180).toFloat()

/** Wraps an angle into [-PI, PI). */
fun wrapAngle(a: Float): Float {
    var x = (a + PI.toFloat()) % TWO_PI
    if (x < 0) x += TWO_PI
    return x - PI.toFloat()
}

/** Signed shortest angular distance from [from] to [to], in [-PI, PI). */
fun angleDelta(from: Float, to: Float): Float = wrapAngle(to - from)

/** Where a ball will cross the paddle circle if it keeps going straight. */
fun predictedExitAngle(ball: Ball): Float {
    val r = Arena.PADDLE_INNER - ball.radius
    val b = ball.x * ball.vx + ball.y * ball.vy
    val v2 = ball.vx * ball.vx + ball.vy * ball.vy
    if (v2 < 1e-9f) return atan2(ball.y, ball.x)
    val c = ball.x * ball.x + ball.y * ball.y - r * r
    val t = (-b + sqrt(maxOf(0f, b * b - v2 * c))) / v2
    return atan2(ball.y + ball.vy * t, ball.x + ball.vx * t)
}

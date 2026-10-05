package com.orbitbreaker.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Pure-Kotlin simulation of one level. Call [update] once per rendered frame; it advances physics
 * in fixed substeps and returns everything that happened so the UI can react (haptics, effects).
 */
class GameEngine(level: LevelDef, private val random: Random = Random.Default) {

    val state = GameState(level)
    private val events = mutableListOf<GameEvent>()
    private var accumulator = 0f
    private val explosionQueue = ArrayDeque<Pair<Int, Int>>()

    init {
        linkWarps()
        attachBallToPaddle(state.balls.first())
    }

    /** Moves the paddle's target by [delta] radians (positive = clockwise). */
    fun nudgePaddle(delta: Float) {
        state.paddle.target += delta
    }

    /** Points the paddle toward an absolute angle, taking the shortest way round. */
    fun aimPaddle(angle: Float) {
        val p = state.paddle
        p.target += angleDelta(p.target, angle)
    }

    /** Launches the ball during the countdown, or releases balls held by a sticky paddle. */
    fun launch() {
        when (state.phase) {
            Phase.COUNTDOWN -> {
                state.phase = Phase.PLAYING
                state.balls.filter { it.stuck }.forEach { ball ->
                    val dir = state.paddle.angle + PI.toFloat() + (random.nextFloat() - 0.5f) * 20f * DEG
                    ball.vx = cos(dir) * state.ballSpeed
                    ball.vy = sin(dir) * state.ballSpeed
                    ball.stuck = false
                    ball.charged = true
                }
                events += GameEvent.Launched
            }
            Phase.PLAYING -> state.balls.filter { it.stuck }.forEach(::releaseStuck)
            else -> Unit
        }
    }

    fun update(frameSeconds: Float): List<GameEvent> {
        events.clear()
        accumulator += frameSeconds.coerceIn(0f, 0.1f)
        while (accumulator >= Arena.FIXED_STEP) {
            step(Arena.FIXED_STEP)
            accumulator -= Arena.FIXED_STEP
        }
        return events.toList()
    }

    private fun step(dt: Float) {
        if (state.phase == Phase.CLEARED || state.phase == Phase.GAME_OVER) return
        state.clock += dt
        updatePaddle(dt)
        state.rings.forEach { it.rotation += it.rotationSpeedAt(state.clock) * dt }
        state.cores.forEach { it.sinceHit += dt }

        when (state.phase) {
            Phase.COUNTDOWN -> {
                if (state.countdown >= Arena.COUNTDOWN_SECONDS) {
                    events += GameEvent.CountdownTick(Arena.COUNTDOWN_SECONDS)
                }
                val before = ceil(state.countdown).toInt()
                state.countdown -= dt
                val after = ceil(state.countdown).toInt()
                if (after < before && after > 0) events += GameEvent.CountdownTick(after)
                state.balls.forEach { if (it.stuck) attachBallToPaddle(it) }
                if (state.countdown <= 0f) launch()
            }
            Phase.PLAYING -> {
                state.elapsed += dt
                state.sinceBrickHit += dt
                if (state.sinceBrickHit > Arena.STALL_SECONDS && !state.stallNudgePending) {
                    state.stallNudgePending = true
                    events += GameEvent.StallNudge
                }
                updateBricks(dt)
                updateEffects(dt)
                moveBalls(dt)
                if (state.phase != Phase.PLAYING) return
                movePowerUps(dt)
                updateLaser(dt)
            }
            else -> Unit
        }
    }

    // region Paddle

    private fun updatePaddle(dt: Float) {
        val p = state.paddle
        val previous = p.angle
        // Exponential ease toward the target (~40 ms time constant): instant-feeling but not jittery.
        p.angle += (p.target - p.angle) * (1f - exp(-dt / 0.04f))
        p.omega = (p.angle - previous) / dt

        // Some levels squeeze the paddle as time goes on.
        val shrink = state.level.paddleShrinkDps * DEG / 2f * state.elapsed
        val base = max(p.baseHalfArc - shrink, Arena.MIN_PADDLE_ARC_DEG * DEG / 2f).coerceAtMost(p.baseHalfArc)
        val widthFactor = when {
            state.isActive(PowerUpType.WIDE) -> Arena.WIDE_FACTOR
            state.isActive(PowerUpType.SHRINK) -> Arena.SHRINK_FACTOR
            else -> 1f
        }
        p.halfArc += (base * widthFactor - p.halfArc) * (1f - exp(-dt / 0.15f))
    }

    private fun attachBallToPaddle(ball: Ball) {
        val r = Arena.PADDLE_INNER - Arena.BALL_RADIUS - 0.005f
        val a = state.paddle.angle + ball.stickOffset
        ball.x = cos(a) * r
        ball.y = sin(a) * r
        ball.vx = 0f
        ball.vy = 0f
        ball.stuck = true
    }

    /**
     * Direction for a ball leaving the paddle at [angle], deflected by [theta] from straight inward.
     * Like classic breakout, hitting one side of the paddle sends the ball toward that side.
     */
    private fun bounceDirection(angle: Float, theta: Float): Pair<Float, Float> {
        val nx = cos(angle)
        val ny = sin(angle)
        val tx = -ny
        val ty = nx
        return (-nx * cos(theta) + tx * sin(theta)) to (-ny * cos(theta) + ty * sin(theta))
    }

    private fun releaseStuck(ball: Ball) {
        val p = state.paddle
        val offset = (ball.stickOffset / p.halfArc).coerceIn(-1f, 1f)
        val (dx, dy) = bounceDirection(p.angle + ball.stickOffset, offset * Arena.MAX_DEFLECT_DEG * DEG)
        ball.vx = dx * state.ballSpeed
        ball.vy = dy * state.ballSpeed
        ball.stuck = false
        ball.stickOffset = 0f
        ball.charged = true
        events += GameEvent.Launched
    }

    // endregion

    // region Balls

    private fun moveBalls(dt: Float) {
        val iterator = state.balls.iterator()
        while (iterator.hasNext()) {
            val ball = iterator.next()
            if (ball.stuck) {
                attachBallToPaddle(ball)
                ball.stickTimer -= dt
                if (ball.stickTimer <= 0f) releaseStuck(ball)
                continue
            }
            ball.warpCooldown -= dt
            // Cap movement per substep to half a ball radius so fast balls can't tunnel through bricks.
            val distance = state.ballSpeed * dt
            val substeps = max(1, ceil(distance / (ball.radius * 0.5f)).toInt())
            val h = dt / substeps
            for (s in 0 until substeps) {
                applyGravity(ball, h)
                ball.x += ball.vx * h
                ball.y += ball.vy * h
                collideCore(ball)
                if (state.phase != Phase.PLAYING) return
                collideBricks(ball)
                if (state.phase != Phase.PLAYING) return
                collidePaddle(ball)
                if (ball.stuck) break
                collideShield(ball)
            }
            checkMissWarning(ball)
            if (hypot(ball.x, ball.y) > Arena.KILL_RADIUS) {
                iterator.remove()
                if (state.balls.isNotEmpty()) events += GameEvent.BallDropped
            }
        }
        if (state.balls.isEmpty()) loseBall()
    }

    private fun checkMissWarning(ball: Ball) {
        val d = hypot(ball.x, ball.y)
        if (d < 1e-4f) return
        val outward = (ball.x * ball.vx + ball.y * ball.vy) / d
        if (outward <= 0f) {
            ball.missWarned = false
            return
        }
        if (ball.missWarned || state.shield) return
        val timeToRing = (Arena.PADDLE_INNER - ball.radius - d) / outward
        if (timeToRing < 0f || timeToRing > Arena.MISS_WARNING_SECONDS) return
        // Judge against where the player is steering, so turning the crown in time cancels the warning.
        val p = state.paddle
        val slack = asin(min(1f, ball.radius / Arena.PADDLE_INNER))
        if (abs(angleDelta(p.target, predictedExitAngle(ball))) > p.halfArc + slack) {
            ball.missWarned = true
            events += GameEvent.MissWarning
        }
    }

    /** Bends the ball toward gravity wells while keeping its speed constant. */
    private fun applyGravity(ball: Ball, h: Float) {
        var ax = 0f
        var ay = 0f
        fun pull(wx: Float, wy: Float, strength: Float) {
            val dx = wx - ball.x
            val dy = wy - ball.y
            val d2 = max(dx * dx + dy * dy, 0.01f)
            val d = sqrt(d2)
            ax += strength / d2 * dx / d
            ay += strength / d2 * dy / d
        }
        state.wells.forEach { w ->
            val s = if (w.pulseSeconds > 0f) {
                w.strength * (0.5f + 0.5f * sin(state.clock * 2f * PI.toFloat() / w.pulseSeconds))
            } else {
                w.strength
            }
            pull(w.x, w.y, s)
        }
        state.cores.forEach { if (it.alive && it.gravity > 0f) pull(it.x, it.y, it.gravity) }
        ball.vx += ax * h
        ball.vy += ay * h
        val speed = hypot(ball.vx, ball.vy)
        if (speed > 1e-6f) {
            ball.vx *= state.ballSpeed / speed
            ball.vy *= state.ballSpeed / speed
        }
    }

    private fun collidePaddle(ball: Ball) {
        val d = hypot(ball.x, ball.y)
        if (d < 1e-4f) return
        val nx = ball.x / d
        val ny = ball.y / d
        val outward = ball.vx * nx + ball.vy * ny
        if (outward <= 0f) return
        if (d + ball.radius < Arena.PADDLE_INNER || d > Arena.PADDLE_RADIUS) return

        val p = state.paddle
        val diff = angleDelta(p.angle, atan2(ball.y, ball.x))
        val ballHalfAngle = asin(min(1f, ball.radius / d))
        if (abs(diff) > p.halfArc + ballHalfAngle) return

        state.combo = 0
        state.speed = min(state.speed * (1f + Arena.SPEED_RAMP_PER_HIT), state.baseSpeed * Arena.MAX_SPEED_FACTOR)

        if (state.isActive(PowerUpType.STICKY)) {
            ball.stickOffset = diff.coerceIn(-p.halfArc, p.halfArc)
            ball.stickTimer = Arena.STICKY_HOLD_SECONDS
            attachBallToPaddle(ball)
            events += GameEvent.BallCaught
            return
        }

        val offset = (diff / p.halfArc).coerceIn(-1f, 1f)
        var theta = offset * Arena.MAX_DEFLECT_DEG * DEG
        // Moving the paddle as the ball lands adds a little spin in the direction of travel.
        theta += (p.omega * 0.05f).coerceIn(-15f * DEG, 15f * DEG)
        if (state.stallNudgePending) {
            theta += (if (random.nextBoolean()) 1 else -1) * Arena.STALL_NUDGE_DEG * DEG
            state.stallNudgePending = false
            state.sinceBrickHit = 0f
        }
        val maxDeflect = Arena.ABSOLUTE_MAX_DEFLECT_DEG * DEG
        theta = theta.coerceIn(-maxDeflect, maxDeflect)

        val (dx, dy) = bounceDirection(atan2(ny, nx), theta)
        ball.vx = dx * state.ballSpeed
        ball.vy = dy * state.ballSpeed
        ball.charged = true
        val r = Arena.PADDLE_INNER - ball.radius
        ball.x = nx * r
        ball.y = ny * r
        events += GameEvent.PaddleHit(offset)
    }

    /** A shield ring just outside the paddle bounces one missed ball back, then disappears. */
    private fun collideShield(ball: Ball) {
        if (!state.shield) return
        val d = hypot(ball.x, ball.y)
        if (d + ball.radius < Arena.SHIELD_RADIUS) return
        val nx = ball.x / d
        val ny = ball.y / d
        val vn = ball.vx * nx + ball.vy * ny
        if (vn <= 0f) return
        ball.vx -= 2f * vn * nx
        ball.vy -= 2f * vn * ny
        val r = Arena.SHIELD_RADIUS - ball.radius
        ball.x = nx * r
        ball.y = ny * r
        state.shield = false
        events += GameEvent.ShieldSaved
    }

    // endregion

    // region Core (boss)

    private fun collideCore(ball: Ball) {
        for (core in state.cores) {
            if (!core.alive) continue
            val dx = ball.x - core.x
            val dy = ball.y - core.y
            val d = hypot(dx, dy)
            val minD = core.radius + ball.radius
            if (d >= minD) continue
            val nx = if (d > 1e-5f) dx / d else 1f
            val ny = if (d > 1e-5f) dy / d else 0f
            val vn = ball.vx * nx + ball.vy * ny
            if (vn < 0f) {
                ball.vx -= 2f * vn * nx
                ball.vy -= 2f * vn * ny
            }
            ball.x = core.x + nx * minD
            ball.y = core.y + ny * minD
            if (ball.charged) {
                ball.charged = false
                hitCore(core)
            } else {
                events += GameEvent.CoreDeflected
            }
            return
        }
    }

    private fun hitCore(core: Core) {
        if (!core.alive) return
        core.hp -= 1
        core.sinceHit = 0f
        state.sinceBrickHit = 0f
        state.stallNudgePending = false
        state.combo += 1
        state.score += Arena.CORE_HIT_SCORE
        events += GameEvent.BossHit(core.hp)

        core.def.phases.forEachIndexed { i, phaseDef ->
            if (i >= core.phase && core.hp <= phaseDef.atHp && core.hp > 0) {
                core.phase = i + 1
                applyBossPhase(core, phaseDef)
                events += GameEvent.BossPhase(core.phase)
            }
        }
        if (!core.alive) {
            state.score += Arena.CORE_DEFEAT_SCORE
            events += GameEvent.BossDefeated
            if (state.cores.none { it.alive }) clearLevel()
        }
    }

    private fun applyBossPhase(core: Core, def: CorePhaseDef) {
        state.rings.forEach { it.speedMultiplier = def.ringSpeedMultiplier }
        core.gravity = def.gravity
        state.rings.filter { it.def.shield }.forEach { ring ->
            ring.bricks.forEach { brick ->
                if (brick == null || !brick.type.breakable) return@forEach
                if (def.restoreShields) {
                    brick.hp = brick.type.hitPoints
                    brick.revealed = brick.type != BrickType.GHOST
                }
                if (def.phaseShields) brick.phasing = true
            }
        }
    }

    // endregion

    // region Bricks

    private data class Hit(val nx: Float, val ny: Float, val penetration: Float, val ring: Int, val index: Int)

    private fun collideBricks(ball: Ball) {
        val d = hypot(ball.x, ball.y)
        val ballAngle = atan2(ball.y, ball.x)
        var best: Hit? = null
        val reach = ball.radius + Arena.SONAR_RANGE

        state.rings.forEachIndexed { ri, ring ->
            if (d + reach < ring.inner || d - reach > ring.outer) return@forEachIndexed
            ring.bricks.forEachIndexed { bi, brick ->
                if (brick == null || !brick.alive) return@forEachIndexed
                if (!state.isTangible(ri, bi)) return@forEachIndexed
                if (brick.type == BrickType.WARP && ball.warpCooldown > 0f) return@forEachIndexed
                val (cx, cy) = closestPoint(ball, d, ballAngle, ring, bi)
                val dx = ball.x - cx
                val dy = ball.y - cy
                val dist = sqrt(dx * dx + dy * dy)

                // Sonar: hidden ghosts always, and every brick on dark levels.
                val sonar = !brick.revealed || state.level.darkness >= Arena.DARK_SONAR_THRESHOLD
                if (sonar && dist < reach && brick.sonarCooldown <= 0f) {
                    brick.sonarCooldown = Arena.SONAR_COOLDOWN
                    events += GameEvent.GhostNear
                }
                if (dist >= ball.radius) return@forEachIndexed
                val hit = if (dist > 1e-5f) {
                    Hit(dx / dist, dy / dist, ball.radius - dist, ri, bi)
                } else {
                    insideHit(ball, d, ballAngle, ring, ri, bi)
                }
                if (best == null || hit.penetration > best!!.penetration) best = hit
            }
        }
        best?.let { resolveBrickHit(ball, it) }
    }

    /** Closest point on an annular-sector brick to the ball center. */
    private fun closestPoint(ball: Ball, d: Float, ballAngle: Float, ring: Ring, i: Int): Pair<Float, Float> {
        val start = ring.startAngle(i)
        val end = ring.endAngle(i)
        val mid = (start + end) / 2f
        val half = (end - start) / 2f
        val rel = angleDelta(mid, ballAngle)
        if (abs(rel) <= half) {
            val cr = d.coerceIn(ring.inner, ring.outer)
            return cos(ballAngle) * cr to sin(ballAngle) * cr
        }
        val edge = if (rel > 0) end else start
        val ex = cos(edge)
        val ey = sin(edge)
        val proj = (ball.x * ex + ball.y * ey).coerceIn(ring.inner, ring.outer)
        return ex * proj to ey * proj
    }

    /** Ball center is inside the brick: push out through the nearest face. */
    private fun insideHit(ball: Ball, d: Float, ballAngle: Float, ring: Ring, ri: Int, bi: Int): Hit {
        val half = (ring.endAngle(bi) - ring.startAngle(bi)) / 2f
        val rel = angleDelta(ring.midAngle(bi), ballAngle)
        val rx = cos(ballAngle)
        val ry = sin(ballAngle)
        val faces = listOf(
            Triple(-rx, -ry, d - ring.inner),
            Triple(rx, ry, ring.outer - d),
            Triple(-ry, rx, (half - rel) * d),
            Triple(ry, -rx, (half + rel) * d),
        )
        val (fx, fy, depth) = faces.minBy { it.third }
        return Hit(fx, fy, ball.radius + depth, ri, bi)
    }

    private fun resolveBrickHit(ball: Ball, hit: Hit) {
        val brick = state.rings[hit.ring].bricks[hit.index] ?: return

        if (brick.type == BrickType.WARP) {
            warp(ball, hit.ring, hit.index)
            return
        }
        // A fireball smashes straight through anything breakable.
        if (state.isActive(PowerUpType.FIRE) && brick.type.breakable) {
            damageBrick(hit.ring, hit.index, brick.hp)
            processExplosions()
            return
        }

        // Reflect only if the ball moves into the surface, then push it out of the brick.
        val vn = ball.vx * hit.nx + ball.vy * hit.ny
        if (vn < 0f) {
            ball.vx -= 2f * vn * hit.nx
            ball.vy -= 2f * vn * hit.ny
        }
        ball.x += hit.nx * hit.penetration
        ball.y += hit.ny * hit.penetration

        if (!brick.type.breakable) {
            events += GameEvent.UnbreakableHit
            return
        }
        damageBrick(hit.ring, hit.index, 1)
        processExplosions()
    }

    /** Teleports the ball to the linked portal, keeping its position and heading relative to the portal. */
    private fun warp(ball: Ball, ri: Int, bi: Int) {
        val (pr, pi) = state.rings[ri].bricks[bi]?.warpPartner ?: return
        val from = state.rings[ri]
        val to = state.rings[pr]
        val rotation = to.midAngle(pi) - from.midAngle(bi)
        val d = hypot(ball.x, ball.y)
        val radial = to.radius + (d - from.radius)
        val angle = atan2(ball.y, ball.x) + rotation
        ball.x = cos(angle) * radial
        ball.y = sin(angle) * radial
        val c = cos(rotation)
        val s = sin(rotation)
        val vx = ball.vx * c - ball.vy * s
        val vy = ball.vx * s + ball.vy * c
        ball.vx = vx
        ball.vy = vy
        ball.warpCooldown = Arena.WARP_COOLDOWN
        events += GameEvent.Warped(ball.x, ball.y)
    }

    private fun linkWarps() {
        val warps = state.rings.flatMapIndexed { ri, ring ->
            ring.bricks.mapIndexedNotNull { bi, b -> if (b?.type == BrickType.WARP) ri to bi else null }
        }
        warps.chunked(2).forEachIndexed { pair, chunk ->
            if (chunk.size < 2) return@forEachIndexed
            val (a, b) = chunk
            state.rings[a.first].bricks[a.second]!!.apply { warpPartner = b; warpPair = pair }
            state.rings[b.first].bricks[b.second]!!.apply { warpPartner = a; warpPair = pair }
        }
    }

    private fun damageBrick(ri: Int, bi: Int, amount: Int) {
        val brick = state.rings[ri].bricks[bi] ?: return
        if (!brick.alive || !brick.type.breakable) return
        state.sinceBrickHit = 0f
        state.stallNudgePending = false
        state.combo += 1
        comboMilestone(state.combo)?.let { events += GameEvent.ComboMilestone(it, state.combo) }

        if (!brick.revealed) {
            brick.revealed = true
            brick.hp -= 1
            state.score += 5
            events += GameEvent.GhostRevealed(ri, bi)
            if (amount <= 1) return
        }
        brick.hp -= amount
        if (brick.alive) {
            state.score += 5
            events += GameEvent.BrickDamaged(ri, bi, brick.hp)
            return
        }
        destroyBrick(ri, bi)
    }

    private fun destroyBrick(ri: Int, bi: Int) {
        val ring = state.rings[ri]
        val brick = ring.bricks[bi] ?: return
        brick.hp = 0
        val angle = ring.midAngle(bi)
        val x = cos(angle) * ring.radius
        val y = sin(angle) * ring.radius
        state.score += 10 * brick.type.hitPoints.coerceAtMost(3) * (1 + state.combo / 5)
        events += GameEvent.BrickDestroyed(ri, bi, brick.type, x, y)

        when (brick.type) {
            BrickType.EXPLOSIVE -> explosionQueue.addLast(ri to bi)
            BrickType.REGEN -> brick.regenTimer = state.level.regenSeconds
            else -> Unit
        }
        if (brick.type == BrickType.CARRIER || random.nextFloat() < state.level.dropChance) spawnPowerUp(x, y)
        if (state.cores.isEmpty() && state.breakableRemaining == 0) clearLevel()
    }

    /** Explosions destroy every breakable neighbour; explosive neighbours chain. */
    private fun processExplosions() {
        while (explosionQueue.isNotEmpty()) {
            val (ri, bi) = explosionQueue.removeFirst()
            val ring = state.rings[ri]
            val angle = ring.midAngle(bi)
            events += GameEvent.Explosion(cos(angle) * ring.radius, sin(angle) * ring.radius)
            neighbours(ri, bi).forEach { (nr, ni) ->
                val n = state.rings[nr].bricks[ni]
                if (n != null && n.alive && n.type.breakable) {
                    n.revealed = true
                    destroyBrick(nr, ni)
                }
            }
        }
    }

    private fun neighbours(ri: Int, bi: Int): List<Pair<Int, Int>> {
        val ring = state.rings[ri]
        val result = mutableListOf(ri to (bi + 1) % ring.sectors, ri to (bi - 1 + ring.sectors) % ring.sectors)
        val mid = ring.midAngle(bi)
        val half = ring.span / 2f
        state.rings.forEachIndexed { rj, other ->
            if (rj == ri || abs(other.radius - ring.radius) > Arena.BRICK_THICKNESS + Arena.EXPLOSION_REACH * 2) {
                return@forEachIndexed
            }
            for (j in 0 until other.sectors) {
                val gap = abs(angleDelta(mid, other.midAngle(j)))
                if (gap < half + other.span / 2f + Arena.EXPLOSION_REACH / other.radius) result += rj to j
            }
        }
        return result
    }

    private fun updateBricks(dt: Float) {
        state.rings.forEachIndexed { ri, ring ->
            ring.bricks.forEachIndexed { bi, brick ->
                if (brick == null) return@forEachIndexed
                brick.sonarCooldown -= dt
                if (brick.type == BrickType.REGEN && !brick.alive && brick.regenTimer > 0f) {
                    brick.regenTimer -= dt
                    if (brick.regenTimer <= 0f) {
                        brick.regenTimer = 0f
                        // Regrowth needs living neighbours: once a whole ring is cleared, it stays clear.
                        if (ring.bricks.any { it != null && it.alive && it.type.breakable }) {
                            brick.hp = brick.type.hitPoints
                            events += GameEvent.BrickRegenerated(ri, bi)
                        }
                    }
                }
            }
        }
    }

    private fun comboMilestone(combo: Int): Int? = when (combo) {
        5 -> 1
        10 -> 2
        20 -> 3
        else -> null
    }

    // endregion

    // region Power-ups

    private fun spawnPowerUp(x: Float, y: Float) {
        val pool = state.level.powerUps.ifEmpty { PowerUpType.entries }
        var pick = random.nextFloat() * pool.sumOf { it.weight.toDouble() }.toFloat()
        val type = pool.firstOrNull { pick -= it.weight; pick <= 0f } ?: pool.last()
        state.powerUps += FallingPowerUp(type, x, y)
        events += GameEvent.PowerUpSpawned(type)
    }

    /** Power-ups drift outward toward the paddle ring; catch them with the paddle. */
    private fun movePowerUps(dt: Float) {
        val p = state.paddle
        val iterator = state.powerUps.iterator()
        while (iterator.hasNext()) {
            val pu = iterator.next()
            var d = hypot(pu.x, pu.y)
            if (d < 1e-4f) {
                pu.x = 0.001f
                d = 0.001f
            }
            pu.x += pu.x / d * Arena.POWERUP_SPEED * dt
            pu.y += pu.y / d * Arena.POWERUP_SPEED * dt
            d = hypot(pu.x, pu.y)
            if (d + Arena.POWERUP_RADIUS >= Arena.PADDLE_INNER && d <= Arena.PADDLE_OUTER) {
                val diff = angleDelta(p.angle, atan2(pu.y, pu.x))
                if (abs(diff) <= p.halfArc + Arena.POWERUP_RADIUS / d) {
                    iterator.remove()
                    collect(pu)
                    continue
                }
            }
            if (d > Arena.KILL_RADIUS) iterator.remove()
        }
    }

    private fun collect(pu: FallingPowerUp) {
        val type = pu.type
        when (type) {
            PowerUpType.WIDE -> state.effects.remove(PowerUpType.SHRINK)
            PowerUpType.SHRINK -> state.effects.remove(PowerUpType.WIDE)
            PowerUpType.MULTI -> splitBalls()
            PowerUpType.SHIELD -> state.shield = true
            PowerUpType.LIFE -> state.lives = min(state.lives + 1, Arena.MAX_LIVES)
            else -> Unit
        }
        if (type.duration > 0f) state.effects[type] = type.duration
        events += GameEvent.PowerUpCollected(type, pu.x, pu.y)
    }

    private fun splitBalls() {
        val source = state.balls.firstOrNull { !it.stuck } ?: state.balls.firstOrNull()?.also(::releaseStuck) ?: return
        val spread = Arena.MULTI_SPREAD_DEG * DEG
        for (sign in listOf(-1f, 1f)) {
            if (state.balls.size >= Arena.MAX_BALLS) break
            val c = cos(sign * spread)
            val s = sin(sign * spread)
            state.balls += Ball(
                x = source.x,
                y = source.y,
                vx = source.vx * c - source.vy * s,
                vy = source.vx * s + source.vy * c,
                stuck = false,
            ).also { it.charged = source.charged }
        }
    }

    private fun updateEffects(dt: Float) {
        val iterator = state.effects.entries.iterator()
        while (iterator.hasNext()) {
            val effect = iterator.next()
            val before = effect.value
            effect.setValue(before - dt)
            if (before > Arena.POWERUP_WARNING_SECONDS && effect.value <= Arena.POWERUP_WARNING_SECONDS) {
                events += GameEvent.PowerUpEnding(effect.key)
            }
            if (effect.value <= 0f) {
                iterator.remove()
                events += GameEvent.PowerUpExpired(effect.key)
                if (effect.key == PowerUpType.STICKY) state.balls.filter { it.stuck }.forEach(::releaseStuck)
            }
        }
    }

    /** While the laser is active, both ends of the paddle fire bolts inward. */
    private fun updateLaser(dt: Float) {
        if (state.isActive(PowerUpType.LASER)) {
            state.laserCooldown -= dt
            if (state.laserCooldown <= 0f) {
                state.laserCooldown = Arena.LASER_INTERVAL
                val p = state.paddle
                for (sign in listOf(-1f, 1f)) {
                    val a = p.angle + sign * p.halfArc * 0.8f
                    state.bolts += LaserBolt(
                        x = cos(a) * Arena.PADDLE_INNER,
                        y = sin(a) * Arena.PADDLE_INNER,
                        vx = -cos(a) * Arena.LASER_SPEED,
                        vy = -sin(a) * Arena.LASER_SPEED,
                    )
                }
                events += GameEvent.LaserFired
            }
        }
        val iterator = state.bolts.iterator()
        while (iterator.hasNext()) {
            val bolt = iterator.next()
            bolt.x += bolt.vx * dt
            bolt.y += bolt.vy * dt
            bolt.traveled += Arena.LASER_SPEED * dt
            if (boltHit(bolt) || bolt.traveled > 1.9f) iterator.remove()
            if (state.phase != Phase.PLAYING) return
        }
    }

    private fun boltHit(bolt: LaserBolt): Boolean {
        val d = hypot(bolt.x, bolt.y)
        state.cores.forEach { core ->
            if (core.alive && hypot(bolt.x - core.x, bolt.y - core.y) < core.radius) {
                hitCore(core)
                return true
            }
        }
        val angle = atan2(bolt.y, bolt.x)
        state.rings.forEachIndexed { ri, ring ->
            if (d < ring.inner || d > ring.outer) return@forEachIndexed
            ring.bricks.forEachIndexed { bi, brick ->
                if (brick == null || !state.isTangible(ri, bi)) return@forEachIndexed
                val half = (ring.endAngle(bi) - ring.startAngle(bi)) / 2f
                if (abs(angleDelta(ring.midAngle(bi), angle)) > half) return@forEachIndexed
                if (brick.type.breakable) {
                    damageBrick(ri, bi, 1)
                    processExplosions()
                }
                return true
            }
        }
        return false
    }

    // endregion

    // region Level flow

    private fun clearLevel() {
        if (state.phase == Phase.CLEARED) return
        state.phase = Phase.CLEARED
        state.stars = 1 +
            (if (state.livesLost == 0) 1 else 0) +
            (if (state.elapsed <= state.level.parSeconds) 1 else 0)
        state.score += state.lives * 100
        events += GameEvent.LevelCleared(state.stars, state.score)
    }

    private fun loseBall() {
        state.lives -= 1
        state.livesLost += 1
        state.combo = 0
        state.speed = state.baseSpeed
        state.powerUps.clear()
        state.bolts.clear()
        state.effects.clear()
        events += GameEvent.BallLost(state.lives)
        if (state.lives <= 0) {
            state.phase = Phase.GAME_OVER
            events += GameEvent.GameOver
            return
        }
        state.balls += Ball().also(::attachBallToPaddle)
        state.phase = Phase.COUNTDOWN
        state.countdown = Arena.COUNTDOWN_SECONDS.toFloat()
        state.sinceBrickHit = 0f
        state.stallNudgePending = false
    }

    // endregion
}

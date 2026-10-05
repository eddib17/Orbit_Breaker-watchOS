import Foundation

/// Pure-Swift simulation of one level. Call `update(frameSeconds:)` once per rendered frame; it
/// advances physics in fixed substeps and returns everything that happened so the UI can react
/// (haptics, effects).
public final class GameEngine {

    public let state: GameState
    private var rng: any RandomNumberGenerator
    private var events: [GameEvent] = []
    private var accumulator: Float = 0
    private var explosionQueue: [BrickRef] = []

    public init(level: LevelDef, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        state = GameState(level: level)
        self.rng = rng
        linkWarps()
        attachBallToPaddle(state.balls[0])
    }

    /// Moves the paddle's target by `delta` radians (positive = clockwise).
    public func nudgePaddle(_ delta: Float) {
        state.paddle.target += delta
    }

    /// Points the paddle toward an absolute angle, taking the shortest way round.
    public func aimPaddle(_ angle: Float) {
        let p = state.paddle
        p.target += angleDelta(p.target, angle)
    }

    /// Launches the ball during the countdown, or releases balls held by a sticky paddle.
    public func launch() {
        switch state.phase {
        case .countdown:
            state.phase = .playing
            for ball in state.balls where ball.stuck {
                let dir = state.paddle.angle + .pi + (rng.nextFloat() - 0.5) * 20 * deg
                ball.vx = cos(dir) * state.ballSpeed
                ball.vy = sin(dir) * state.ballSpeed
                ball.stuck = false
                ball.charged = true
            }
            events.append(.launched)
        case .playing:
            for ball in state.balls where ball.stuck { releaseStuck(ball) }
        default:
            break
        }
    }

    public func update(frameSeconds: Float) -> [GameEvent] {
        events.removeAll(keepingCapacity: true)
        accumulator += frameSeconds.clamped(0, 0.1)
        while accumulator >= Arena.fixedStep {
            step(Arena.fixedStep)
            accumulator -= Arena.fixedStep
        }
        return events
    }

    private func step(_ dt: Float) {
        if state.phase == .cleared || state.phase == .gameOver { return }
        state.clock += dt
        updatePaddle(dt)
        for ring in state.rings { ring.rotation += ring.rotationSpeed(at: state.clock) * dt }
        for core in state.cores { core.sinceHit += dt }

        switch state.phase {
        case .countdown:
            if state.countdown >= Float(Arena.countdownSeconds) {
                events.append(.countdownTick(remaining: Arena.countdownSeconds))
            }
            let before = Int(state.countdown.rounded(.up))
            state.countdown -= dt
            let after = Int(state.countdown.rounded(.up))
            if after < before && after > 0 { events.append(.countdownTick(remaining: after)) }
            for ball in state.balls where ball.stuck { attachBallToPaddle(ball) }
            if state.countdown <= 0 { launch() }
        case .playing:
            state.elapsed += dt
            state.sinceBrickHit += dt
            if state.sinceBrickHit > Arena.stallSeconds && !state.stallNudgePending {
                state.stallNudgePending = true
                events.append(.stallNudge)
            }
            updateBricks(dt)
            updateEffects(dt)
            moveBalls(dt)
            if state.phase != .playing { return }
            movePowerUps(dt)
            updateLaser(dt)
        default:
            break
        }
    }

    // MARK: - Paddle

    private func updatePaddle(_ dt: Float) {
        let p = state.paddle
        let previous = p.angle
        // Exponential ease toward the target (~40 ms time constant): instant-feeling but not jittery.
        p.angle += (p.target - p.angle) * (1 - exp(-dt / 0.04))
        p.omega = (p.angle - previous) / dt

        // Some levels squeeze the paddle as time goes on.
        let shrink = state.level.paddleShrinkDps * deg / 2 * state.elapsed
        let base = min(max(p.baseHalfArc - shrink, Arena.minPaddleArcDeg * deg / 2), p.baseHalfArc)
        let widthFactor: Float =
            if state.isActive(.wide) { Arena.wideFactor }
            else if state.isActive(.shrink) { Arena.shrinkFactor }
            else { 1 }
        p.halfArc += (base * widthFactor - p.halfArc) * (1 - exp(-dt / 0.15))
    }

    private func attachBallToPaddle(_ ball: Ball) {
        let r = Arena.paddleInner - Arena.ballRadius - 0.005
        let a = state.paddle.angle + ball.stickOffset
        ball.x = cos(a) * r
        ball.y = sin(a) * r
        ball.vx = 0
        ball.vy = 0
        ball.stuck = true
    }

    /// Direction for a ball leaving the paddle at `angle`, deflected by `theta` from straight inward.
    /// Like classic breakout, hitting one side of the paddle sends the ball toward that side.
    private func bounceDirection(_ angle: Float, _ theta: Float) -> (Float, Float) {
        let nx = cos(angle)
        let ny = sin(angle)
        let tx = -ny
        let ty = nx
        return (-nx * cos(theta) + tx * sin(theta), -ny * cos(theta) + ty * sin(theta))
    }

    private func releaseStuck(_ ball: Ball) {
        let p = state.paddle
        let offset = (ball.stickOffset / p.halfArc).clamped(-1, 1)
        let (dx, dy) = bounceDirection(p.angle + ball.stickOffset, offset * Arena.maxDeflectDeg * deg)
        ball.vx = dx * state.ballSpeed
        ball.vy = dy * state.ballSpeed
        ball.stuck = false
        ball.stickOffset = 0
        ball.charged = true
        events.append(.launched)
    }

    // MARK: - Balls

    private func moveBalls(_ dt: Float) {
        var i = 0
        while i < state.balls.count {
            let ball = state.balls[i]
            if ball.stuck {
                attachBallToPaddle(ball)
                ball.stickTimer -= dt
                if ball.stickTimer <= 0 { releaseStuck(ball) }
                i += 1
                continue
            }
            ball.warpCooldown -= dt
            // Cap movement per substep to half a ball radius so fast balls can't tunnel through bricks.
            let distance = state.ballSpeed * dt
            let substeps = max(1, Int((distance / (ball.radius * 0.5)).rounded(.up)))
            let h = dt / Float(substeps)
            for _ in 0..<substeps {
                applyGravity(ball, h)
                ball.x += ball.vx * h
                ball.y += ball.vy * h
                collideCore(ball)
                if state.phase != .playing { return }
                collideBricks(ball)
                if state.phase != .playing { return }
                collidePaddle(ball)
                if ball.stuck { break }
                collideShield(ball)
            }
            checkMissWarning(ball)
            if norm(ball.x, ball.y) > Arena.killRadius {
                state.balls.remove(at: i)
                if !state.balls.isEmpty { events.append(.ballDropped) }
            } else {
                i += 1
            }
        }
        if state.balls.isEmpty { loseBall() }
    }

    private func checkMissWarning(_ ball: Ball) {
        let d = norm(ball.x, ball.y)
        if d < 1e-4 { return }
        let outward = (ball.x * ball.vx + ball.y * ball.vy) / d
        if outward <= 0 {
            ball.missWarned = false
            return
        }
        if ball.missWarned || state.shield { return }
        let timeToRing = (Arena.paddleInner - ball.radius - d) / outward
        if timeToRing < 0 || timeToRing > Arena.missWarningSeconds { return }
        // Judge against where the player is steering, so turning the crown in time cancels the warning.
        let p = state.paddle
        let slack = asin(min(1, ball.radius / Arena.paddleInner))
        if abs(angleDelta(p.target, predictedExitAngle(ball))) > p.halfArc + slack {
            ball.missWarned = true
            events.append(.missWarning)
        }
    }

    /// Bends the ball toward gravity wells while keeping its speed constant.
    private func applyGravity(_ ball: Ball, _ h: Float) {
        var ax: Float = 0
        var ay: Float = 0
        func pull(_ wx: Float, _ wy: Float, _ strength: Float) {
            let dx = wx - ball.x
            let dy = wy - ball.y
            let d2 = max(dx * dx + dy * dy, 0.01)
            let d = d2.squareRoot()
            ax += strength / d2 * dx / d
            ay += strength / d2 * dy / d
        }
        for w in state.wells {
            let s = w.pulseSeconds > 0
                ? w.strength * (0.5 + 0.5 * sin(state.clock * 2 * .pi / w.pulseSeconds))
                : w.strength
            pull(w.x, w.y, s)
        }
        for core in state.cores where core.alive && core.gravity > 0 { pull(core.x, core.y, core.gravity) }
        ball.vx += ax * h
        ball.vy += ay * h
        let speed = norm(ball.vx, ball.vy)
        if speed > 1e-6 {
            ball.vx *= state.ballSpeed / speed
            ball.vy *= state.ballSpeed / speed
        }
    }

    private func collidePaddle(_ ball: Ball) {
        let d = norm(ball.x, ball.y)
        if d < 1e-4 { return }
        let nx = ball.x / d
        let ny = ball.y / d
        let outward = ball.vx * nx + ball.vy * ny
        if outward <= 0 { return }
        if d + ball.radius < Arena.paddleInner || d > Arena.paddleRadius { return }

        let p = state.paddle
        let diff = angleDelta(p.angle, atan2(ball.y, ball.x))
        let ballHalfAngle = asin(min(1, ball.radius / d))
        if abs(diff) > p.halfArc + ballHalfAngle { return }

        state.combo = 0
        state.speed = min(state.speed * (1 + Arena.speedRampPerHit), state.baseSpeed * Arena.maxSpeedFactor)

        if state.isActive(.sticky) {
            ball.stickOffset = diff.clamped(-p.halfArc, p.halfArc)
            ball.stickTimer = Arena.stickyHoldSeconds
            attachBallToPaddle(ball)
            events.append(.ballCaught)
            return
        }

        let offset = (diff / p.halfArc).clamped(-1, 1)
        var theta = offset * Arena.maxDeflectDeg * deg
        // Moving the paddle as the ball lands adds a little spin in the direction of travel.
        theta += (p.omega * 0.05).clamped(-15 * deg, 15 * deg)
        if state.stallNudgePending {
            theta += (rng.nextBool() ? 1 : -1) * Arena.stallNudgeDeg * deg
            state.stallNudgePending = false
            state.sinceBrickHit = 0
        }
        let maxDeflect = Arena.absoluteMaxDeflectDeg * deg
        theta = theta.clamped(-maxDeflect, maxDeflect)

        let (dx, dy) = bounceDirection(atan2(ny, nx), theta)
        ball.vx = dx * state.ballSpeed
        ball.vy = dy * state.ballSpeed
        ball.charged = true
        let r = Arena.paddleInner - ball.radius
        ball.x = nx * r
        ball.y = ny * r
        events.append(.paddleHit(offset: offset))
    }

    /// A shield ring just outside the paddle bounces one missed ball back, then disappears.
    private func collideShield(_ ball: Ball) {
        if !state.shield { return }
        let d = norm(ball.x, ball.y)
        if d + ball.radius < Arena.shieldRadius { return }
        let nx = ball.x / d
        let ny = ball.y / d
        let vn = ball.vx * nx + ball.vy * ny
        if vn <= 0 { return }
        ball.vx -= 2 * vn * nx
        ball.vy -= 2 * vn * ny
        let r = Arena.shieldRadius - ball.radius
        ball.x = nx * r
        ball.y = ny * r
        state.shield = false
        events.append(.shieldSaved)
    }

    // MARK: - Core (boss)

    private func collideCore(_ ball: Ball) {
        for core in state.cores where core.alive {
            let dx = ball.x - core.x
            let dy = ball.y - core.y
            let d = norm(dx, dy)
            let minD = core.radius + ball.radius
            if d >= minD { continue }
            let nx: Float = d > 1e-5 ? dx / d : 1
            let ny: Float = d > 1e-5 ? dy / d : 0
            let vn = ball.vx * nx + ball.vy * ny
            if vn < 0 {
                ball.vx -= 2 * vn * nx
                ball.vy -= 2 * vn * ny
            }
            ball.x = core.x + nx * minD
            ball.y = core.y + ny * minD
            if ball.charged {
                ball.charged = false
                hitCore(core)
            } else {
                events.append(.coreDeflected)
            }
            return
        }
    }

    private func hitCore(_ core: Core) {
        if !core.alive { return }
        core.hp -= 1
        core.sinceHit = 0
        state.sinceBrickHit = 0
        state.stallNudgePending = false
        state.combo += 1
        state.score += Arena.coreHitScore
        events.append(.bossHit(hpLeft: core.hp))

        for (i, phaseDef) in core.def.phases.enumerated()
        where i >= core.phase && core.hp <= phaseDef.atHp && core.hp > 0 {
            core.phase = i + 1
            applyBossPhase(core, phaseDef)
            events.append(.bossPhase(core.phase))
        }
        if !core.alive {
            state.score += Arena.coreDefeatScore
            events.append(.bossDefeated)
            if !state.cores.contains(where: \.alive) { clearLevel() }
        }
    }

    private func applyBossPhase(_ core: Core, _ def: CorePhaseDef) {
        for ring in state.rings { ring.speedMultiplier = def.ringSpeedMultiplier }
        core.gravity = def.gravity
        for ring in state.rings where ring.def.shield {
            for case let brick? in ring.bricks where brick.type.breakable {
                if def.restoreShields {
                    brick.hp = brick.type.hitPoints
                    brick.revealed = brick.type != .ghost
                }
                if def.phaseShields { brick.phasing = true }
            }
        }
    }

    // MARK: - Bricks

    private struct Hit {
        let nx: Float
        let ny: Float
        let penetration: Float
        let ring: Int
        let index: Int
    }

    private func collideBricks(_ ball: Ball) {
        let d = norm(ball.x, ball.y)
        let ballAngle = atan2(ball.y, ball.x)
        var best: Hit?
        let reach = ball.radius + Arena.sonarRange

        for (ri, ring) in state.rings.enumerated() {
            if d + reach < ring.inner || d - reach > ring.outer { continue }
            for (bi, brick) in ring.bricks.enumerated() {
                guard let brick, brick.alive else { continue }
                if !state.isTangible(ring: ri, index: bi) { continue }
                if brick.type == .warp && ball.warpCooldown > 0 { continue }
                let (cx, cy) = closestPoint(ball, d, ballAngle, ring, bi)
                let dx = ball.x - cx
                let dy = ball.y - cy
                let dist = (dx * dx + dy * dy).squareRoot()

                // Sonar: hidden ghosts always, and every brick on dark levels.
                let sonar = !brick.revealed || state.level.darkness >= Arena.darkSonarThreshold
                if sonar && dist < reach && brick.sonarCooldown <= 0 {
                    brick.sonarCooldown = Arena.sonarCooldown
                    events.append(.ghostNear)
                }
                if dist >= ball.radius { continue }
                let hit = dist > 1e-5
                    ? Hit(nx: dx / dist, ny: dy / dist, penetration: ball.radius - dist, ring: ri, index: bi)
                    : insideHit(ball, d, ballAngle, ring, ri, bi)
                if best == nil || hit.penetration > best!.penetration { best = hit }
            }
        }
        if let best { resolveBrickHit(ball, best) }
    }

    /// Closest point on an annular-sector brick to the ball center.
    private func closestPoint(_ ball: Ball, _ d: Float, _ ballAngle: Float, _ ring: Ring, _ i: Int) -> (Float, Float) {
        let start = ring.startAngle(i)
        let end = ring.endAngle(i)
        let mid = (start + end) / 2
        let half = (end - start) / 2
        let rel = angleDelta(mid, ballAngle)
        if abs(rel) <= half {
            let cr = d.clamped(ring.inner, ring.outer)
            return (cos(ballAngle) * cr, sin(ballAngle) * cr)
        }
        let edge = rel > 0 ? end : start
        let ex = cos(edge)
        let ey = sin(edge)
        let proj = (ball.x * ex + ball.y * ey).clamped(ring.inner, ring.outer)
        return (ex * proj, ey * proj)
    }

    /// Ball center is inside the brick: push out through the nearest face.
    private func insideHit(_ ball: Ball, _ d: Float, _ ballAngle: Float, _ ring: Ring, _ ri: Int, _ bi: Int) -> Hit {
        let half = (ring.endAngle(bi) - ring.startAngle(bi)) / 2
        let rel = angleDelta(ring.midAngle(bi), ballAngle)
        let rx = cos(ballAngle)
        let ry = sin(ballAngle)
        let faces: [(Float, Float, Float)] = [
            (-rx, -ry, d - ring.inner),
            (rx, ry, ring.outer - d),
            (-ry, rx, (half - rel) * d),
            (ry, -rx, (half + rel) * d),
        ]
        let (fx, fy, depth) = faces.min { $0.2 < $1.2 }!
        return Hit(nx: fx, ny: fy, penetration: ball.radius + depth, ring: ri, index: bi)
    }

    private func resolveBrickHit(_ ball: Ball, _ hit: Hit) {
        guard let brick = state.rings[hit.ring].bricks[hit.index] else { return }

        if brick.type == .warp {
            warp(ball, hit.ring, hit.index)
            return
        }
        // A fireball smashes straight through anything breakable.
        if state.isActive(.fire) && brick.type.breakable {
            damageBrick(hit.ring, hit.index, amount: brick.hp)
            processExplosions()
            return
        }

        // Reflect only if the ball moves into the surface, then push it out of the brick.
        let vn = ball.vx * hit.nx + ball.vy * hit.ny
        if vn < 0 {
            ball.vx -= 2 * vn * hit.nx
            ball.vy -= 2 * vn * hit.ny
        }
        ball.x += hit.nx * hit.penetration
        ball.y += hit.ny * hit.penetration

        if !brick.type.breakable {
            events.append(.unbreakableHit)
            return
        }
        damageBrick(hit.ring, hit.index, amount: 1)
        processExplosions()
    }

    /// Teleports the ball to the linked portal, keeping its position and heading relative to the portal.
    private func warp(_ ball: Ball, _ ri: Int, _ bi: Int) {
        guard let partner = state.rings[ri].bricks[bi]?.warpPartner else { return }
        let from = state.rings[ri]
        let to = state.rings[partner.ring]
        let rotation = to.midAngle(partner.index) - from.midAngle(bi)
        let d = norm(ball.x, ball.y)
        let radial = to.radius + (d - from.radius)
        let angle = atan2(ball.y, ball.x) + rotation
        ball.x = cos(angle) * radial
        ball.y = sin(angle) * radial
        let c = cos(rotation)
        let s = sin(rotation)
        let vx = ball.vx * c - ball.vy * s
        let vy = ball.vx * s + ball.vy * c
        ball.vx = vx
        ball.vy = vy
        ball.warpCooldown = Arena.warpCooldown
        events.append(.warped(x: ball.x, y: ball.y))
    }

    private func linkWarps() {
        var warps: [BrickRef] = []
        for (ri, ring) in state.rings.enumerated() {
            for (bi, brick) in ring.bricks.enumerated() where brick?.type == .warp {
                warps.append(BrickRef(ring: ri, index: bi))
            }
        }
        for pair in 0..<(warps.count / 2) {
            let a = warps[pair * 2]
            let b = warps[pair * 2 + 1]
            let brickA = state.rings[a.ring].bricks[a.index]!
            let brickB = state.rings[b.ring].bricks[b.index]!
            brickA.warpPartner = b
            brickA.warpPair = pair
            brickB.warpPartner = a
            brickB.warpPair = pair
        }
    }

    private func damageBrick(_ ri: Int, _ bi: Int, amount: Int) {
        guard let brick = state.rings[ri].bricks[bi], brick.alive, brick.type.breakable else { return }
        state.sinceBrickHit = 0
        state.stallNudgePending = false
        state.combo += 1
        if let tier = comboMilestone(state.combo) {
            events.append(.comboMilestone(tier: tier, combo: state.combo))
        }

        if !brick.revealed {
            brick.revealed = true
            brick.hp -= 1
            state.score += 5
            events.append(.ghostRevealed(ring: ri, index: bi))
            if amount <= 1 { return }
        }
        brick.hp -= amount
        if brick.alive {
            state.score += 5
            events.append(.brickDamaged(ring: ri, index: bi, hpLeft: brick.hp))
            return
        }
        destroyBrick(ri, bi)
    }

    private func destroyBrick(_ ri: Int, _ bi: Int) {
        let ring = state.rings[ri]
        guard let brick = ring.bricks[bi] else { return }
        brick.hp = 0
        let angle = ring.midAngle(bi)
        let x = cos(angle) * ring.radius
        let y = sin(angle) * ring.radius
        state.score += 10 * min(brick.type.hitPoints, 3) * (1 + state.combo / 5)
        events.append(.brickDestroyed(ring: ri, index: bi, type: brick.type, x: x, y: y))

        switch brick.type {
        case .explosive: explosionQueue.append(BrickRef(ring: ri, index: bi))
        case .regen: brick.regenTimer = state.level.regenSeconds
        default: break
        }
        if brick.type == .carrier || rng.nextFloat() < state.level.dropChance { spawnPowerUp(x, y) }
        if state.cores.isEmpty && state.breakableRemaining == 0 { clearLevel() }
    }

    /// Explosions destroy every breakable neighbour; explosive neighbours chain.
    private func processExplosions() {
        while !explosionQueue.isEmpty {
            let source = explosionQueue.removeFirst()
            let ring = state.rings[source.ring]
            let angle = ring.midAngle(source.index)
            events.append(.explosion(x: cos(angle) * ring.radius, y: sin(angle) * ring.radius))
            for n in neighbours(source.ring, source.index) {
                if let brick = state.rings[n.ring].bricks[n.index], brick.alive, brick.type.breakable {
                    brick.revealed = true
                    destroyBrick(n.ring, n.index)
                }
            }
        }
    }

    private func neighbours(_ ri: Int, _ bi: Int) -> [BrickRef] {
        let ring = state.rings[ri]
        var result = [
            BrickRef(ring: ri, index: (bi + 1) % ring.sectors),
            BrickRef(ring: ri, index: (bi - 1 + ring.sectors) % ring.sectors),
        ]
        let mid = ring.midAngle(bi)
        let half = ring.span / 2
        for (rj, other) in state.rings.enumerated() {
            if rj == ri || abs(other.radius - ring.radius) > Arena.brickThickness + Arena.explosionReach * 2 {
                continue
            }
            for j in 0..<other.sectors {
                let gap = abs(angleDelta(mid, other.midAngle(j)))
                if gap < half + other.span / 2 + Arena.explosionReach / other.radius {
                    result.append(BrickRef(ring: rj, index: j))
                }
            }
        }
        return result
    }

    private func updateBricks(_ dt: Float) {
        for (ri, ring) in state.rings.enumerated() {
            for (bi, brick) in ring.bricks.enumerated() {
                guard let brick else { continue }
                brick.sonarCooldown -= dt
                if brick.type == .regen && !brick.alive && brick.regenTimer > 0 {
                    brick.regenTimer -= dt
                    if brick.regenTimer <= 0 {
                        brick.regenTimer = 0
                        // Regrowth needs living neighbours: once a whole ring is cleared, it stays clear.
                        if ring.bricks.contains(where: { $0 != nil && $0!.alive && $0!.type.breakable }) {
                            brick.hp = brick.type.hitPoints
                            events.append(.brickRegenerated(ring: ri, index: bi))
                        }
                    }
                }
            }
        }
    }

    private func comboMilestone(_ combo: Int) -> Int? {
        switch combo {
        case 5: 1
        case 10: 2
        case 20: 3
        default: nil
        }
    }

    // MARK: - Power-ups

    private func spawnPowerUp(_ x: Float, _ y: Float) {
        let pool = state.level.powerUps.isEmpty ? PowerUpType.allCases : state.level.powerUps
        var pick = rng.nextFloat() * pool.reduce(0) { $0 + $1.weight }
        let type = pool.first { pick -= $0.weight; return pick <= 0 } ?? pool.last!
        state.powerUps.append(FallingPowerUp(type: type, x: x, y: y))
        events.append(.powerUpSpawned(type))
    }

    /// Power-ups drift outward toward the paddle ring; catch them with the paddle.
    private func movePowerUps(_ dt: Float) {
        let p = state.paddle
        var i = 0
        while i < state.powerUps.count {
            let pu = state.powerUps[i]
            var d = norm(pu.x, pu.y)
            if d < 1e-4 {
                pu.x = 0.001
                d = 0.001
            }
            pu.x += pu.x / d * Arena.powerUpSpeed * dt
            pu.y += pu.y / d * Arena.powerUpSpeed * dt
            d = norm(pu.x, pu.y)
            if d + Arena.powerUpRadius >= Arena.paddleInner && d <= Arena.paddleOuter {
                let diff = angleDelta(p.angle, atan2(pu.y, pu.x))
                if abs(diff) <= p.halfArc + Arena.powerUpRadius / d {
                    state.powerUps.remove(at: i)
                    collect(pu)
                    continue
                }
            }
            if d > Arena.killRadius {
                state.powerUps.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    private func collect(_ pu: FallingPowerUp) {
        let type = pu.type
        switch type {
        case .wide: state.effects[.shrink] = nil
        case .shrink: state.effects[.wide] = nil
        case .multi: splitBalls()
        case .shield: state.shield = true
        case .life: state.lives = min(state.lives + 1, Arena.maxLives)
        default: break
        }
        if type.duration > 0 { state.effects[type] = type.duration }
        events.append(.powerUpCollected(type, x: pu.x, y: pu.y))
    }

    private func splitBalls() {
        let source: Ball
        if let free = state.balls.first(where: { !$0.stuck }) {
            source = free
        } else if let first = state.balls.first {
            releaseStuck(first)
            source = first
        } else {
            return
        }
        let spread = Arena.multiSpreadDeg * deg
        for sign: Float in [-1, 1] {
            if state.balls.count >= Arena.maxBalls { break }
            let c = cos(sign * spread)
            let s = sin(sign * spread)
            let ball = Ball(
                x: source.x,
                y: source.y,
                vx: source.vx * c - source.vy * s,
                vy: source.vx * s + source.vy * c,
                stuck: false
            )
            ball.charged = source.charged
            state.balls.append(ball)
        }
    }

    private func updateEffects(_ dt: Float) {
        for type in PowerUpType.allCases {
            guard let before = state.effects[type] else { continue }
            let after = before - dt
            state.effects[type] = after
            if before > Arena.powerUpWarningSeconds && after <= Arena.powerUpWarningSeconds {
                events.append(.powerUpEnding(type))
            }
            if after <= 0 {
                state.effects[type] = nil
                events.append(.powerUpExpired(type))
                if type == .sticky {
                    for ball in state.balls where ball.stuck { releaseStuck(ball) }
                }
            }
        }
    }

    /// While the laser is active, both ends of the paddle fire bolts inward.
    private func updateLaser(_ dt: Float) {
        if state.isActive(.laser) {
            state.laserCooldown -= dt
            if state.laserCooldown <= 0 {
                state.laserCooldown = Arena.laserInterval
                let p = state.paddle
                for sign: Float in [-1, 1] {
                    let a = p.angle + sign * p.halfArc * 0.8
                    state.bolts.append(LaserBolt(
                        x: cos(a) * Arena.paddleInner,
                        y: sin(a) * Arena.paddleInner,
                        vx: -cos(a) * Arena.laserSpeed,
                        vy: -sin(a) * Arena.laserSpeed
                    ))
                }
                events.append(.laserFired)
            }
        }
        var i = 0
        while i < state.bolts.count {
            let bolt = state.bolts[i]
            bolt.x += bolt.vx * dt
            bolt.y += bolt.vy * dt
            bolt.traveled += Arena.laserSpeed * dt
            if boltHit(bolt) || bolt.traveled > 1.9 {
                state.bolts.remove(at: i)
            } else {
                i += 1
            }
            if state.phase != .playing { return }
        }
    }

    private func boltHit(_ bolt: LaserBolt) -> Bool {
        let d = norm(bolt.x, bolt.y)
        for core in state.cores where core.alive && norm(bolt.x - core.x, bolt.y - core.y) < core.radius {
            hitCore(core)
            return true
        }
        let angle = atan2(bolt.y, bolt.x)
        for (ri, ring) in state.rings.enumerated() {
            if d < ring.inner || d > ring.outer { continue }
            for (bi, brick) in ring.bricks.enumerated() {
                guard let brick, state.isTangible(ring: ri, index: bi) else { continue }
                let half = (ring.endAngle(bi) - ring.startAngle(bi)) / 2
                if abs(angleDelta(ring.midAngle(bi), angle)) > half { continue }
                if brick.type.breakable {
                    damageBrick(ri, bi, amount: 1)
                    processExplosions()
                }
                return true
            }
        }
        return false
    }

    // MARK: - Level flow

    private func clearLevel() {
        if state.phase == .cleared { return }
        state.phase = .cleared
        state.stars = 1
            + (state.livesLost == 0 ? 1 : 0)
            + (state.elapsed <= Float(state.level.parSeconds) ? 1 : 0)
        state.score += state.lives * 100
        events.append(.levelCleared(stars: state.stars, score: state.score))
    }

    private func loseBall() {
        state.lives -= 1
        state.livesLost += 1
        state.combo = 0
        state.speed = state.baseSpeed
        state.powerUps.removeAll()
        state.bolts.removeAll()
        state.effects.removeAll()
        events.append(.ballLost(livesLeft: state.lives))
        if state.lives <= 0 {
            state.phase = .gameOver
            events.append(.gameOver)
            return
        }
        let ball = Ball()
        attachBallToPaddle(ball)
        state.balls.append(ball)
        state.phase = .countdown
        state.countdown = Float(Arena.countdownSeconds)
        state.sinceBrickHit = 0
        state.stallNudgePending = false
    }
}
